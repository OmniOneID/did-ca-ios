//
/*
 * Copyright 2026 OmniOne.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


import Foundation
import DIDWalletSDK

/// The flow expected by the entry point that started the scan.
///
/// The + button (issuance) and the Present button (submit) share the same scanner screen, but a QR itself can
/// carry either flow. The entry button has already stated the intent, so a QR that differs from it is rejected —
/// so the user never presses "add" and gets a submit screen.
enum ScanIntent {
    /// + → Scan QR. Accepts issuance QRs only.
    case issue
    /// Present → Scan QR. Accepts presentation QRs only.
    case present
    /// Deep link — there is no entry button, so no basis to restrict the flow. Accepts both.
    case any

    /// Whether this entry point may accept the scanned QR's flow.
    func accepts(_ flow: ScanIntent) -> Bool { self == .any || self == flow }
}

// Router that feeds payloads arriving via scan/deep link into the issuance/presentation flow for their kind.
//
// Screen stack, modals and user input state are all owned by AppCoordinator, so it takes that instance as a
// parameter and delegates — all this type knows is "which payload to run through which protocol in what order",
// and it holds no state of its own (hence enum namespace + static). There are two entry points:
//   handle(_:on:)                   QR scan / deep link (the offer is the starting point of the flow)
//   startOID4VciWebIssuance(...)    issuance that picks from the list, then receives the offer via a WebView
enum QRRouter {

    /// Kind of the scanned string — determined by scheme prefix.
    private enum ScannedQRKind { case oid4vp, oid4vci, openDID }

    /// Handles a scanned QR — splits OID4VP / OID4VCI / OpenDID by scheme.
    ///
    /// `intent` is the flow expected by the entry point that started the scan. On a kind mismatch, no flow is started
    /// and only a notice is shown — it must be filtered **before** server calls, auth or screen transitions start, so
    /// the user never has to back out from the middle of the wrong flow.
    static func handle(_ qrString: String,
                       intent: ScanIntent = .any,
                       on coordinator: AppCoordinator) async {
        switch classify(qrString) {
        case .oid4vp:
            guard intent.accepts(.present) else { return reject(intent) }
            await handleOID4VP(qrString, on: coordinator)
        case .oid4vci:
            guard intent.accepts(.issue) else { return reject(intent) }
            await handleOID4VCI(qrString, on: coordinator)
        case .openDID:
            // OpenDID can't tell issuance/presentation from the scheme — decide after reading payloadType.
            await handleOpenDID(qrString, intent: intent, on: coordinator)
        }
    }

    /// A QR of a different kind from the entry button — tells the user where to go.
    /// `.any` (deep link) has no restriction, so it never comes down this path.
    private static func reject(_ intent: ScanIntent) {
        let message: String
        switch intent {
        case .issue:
            message = "This QR code is for presenting a credential. Use Present to submit one."
        case .present:
            message = "This QR code is for issuing a credential. Use + to add one."
        case .any:
            return
        }
        OverlayManager.shared.showPopup(title: "Unexpected QR code",
                                        message: message,
                                        primaryButtonTitle: "OK")
    }

    /// OpenDID payloads are multibase strings, not URL schemes, so they never overlap the `openid*` prefix
    /// → check the two schemes first and feed the rest to OpenDID.
    private static func classify(_ qr: String) -> ScannedQRKind {
        if qr.hasPrefix("openid4vp") { return .oid4vp }
        if qr.hasPrefix("openid-credential-offer") { return .oid4vci }
        return .openDID
    }

    /// Existing OpenDID handling — splits issuance/presentation by payloadType.
    /// The flow is inside the payload, so the `intent` check is also done after decoding.
    private static func handleOpenDID(_ qrString: String,
                                      intent: ScanIntent,
                                      on coordinator: AppCoordinator) async {
        do {
            let dataPayload = try DataPayload(from: qrString)
            let data = try MultibaseUtils.decode(encoded: dataPayload.payload)
            if dataPayload.payloadType == "ISSUE_VC" {
                guard intent.accepts(.issue) else { return reject(intent) }
                await issueFromQR(data: data, on: coordinator)
            } else {
                guard intent.accepts(.present) else { return reject(intent) }
                await presentFromQR(data: data, on: coordinator)
            }
        } catch {
            OverlayManager.shared.showErrorPopup(title: "Invalid QR code", error: error)
        }
    }

    /// OID4VP presentation — parses the `openid4vp://...?request_uri=` authorization request, and if DCQL matching
    /// finds submittable VCs, shows VPRequestView(.oid4vpRequest). Error popup if no VC matches or
    /// parsing/validation fails. The actual submit is handled by submitOID4VP (parallel structure to regular VP).
    private static func handleOID4VP(_ qrString: String, on coordinator: AppCoordinator) async {
        OverlayManager.shared.showLoading()
        defer { OverlayManager.shared.hideLoading() }
        do {
            let authRequest = try await OID4VPPresenter.getAuthorizationRequest(uri: qrString)
            coordinator.oid4vpRequest = authRequest
            // Unlike regular VP, the summary also doubles as the submittability check (matchCredentials) —
            // on failure (noMatchedCredentials, etc.) presentation itself is impossible, so propagate via try for an error popup.
            coordinator.oid4vpSummary = try await OID4VPPresenter.presentationSummary(authRequest: authRequest)
            coordinator.push(.oid4vpRequest)
        } catch is NoSubmittableCredentialError {
            Self.showNoSubmittableCredential(on: coordinator)
        } catch {
            OverlayManager.shared.showErrorPopup(title: "Failed to load presentation", error: error)
        }
    }

    /// OID4VCI issuance — handles `openid-credential-offer://...?credential_offer_uri=` with `IssueOID4VcProtocol`.
    /// The SDK flow (getCredentialOffer → getMetadata → getToken → requestCredential) is
    /// handled by the protocol; here we only orchestrate the UI in between (loading, grant type popup, tx_code modal, holder
    /// auth sheet, success screen). requestCredential handles storing the issued VC too, so
    /// reloading after issuance shows the new card in the wallet list.
    ///
    /// - parameter expecting: filled only for list-based (WebView) issuance — checks that the Issuer/Credential the user
    ///   picked match the returned offer (guide §8). For QR/deep-link issuance the offer is the starting point of the
    ///   flow, so there is no reference value to compare against: nil.
    private static func handleOID4VCI(_ qrString: String,
                                      expecting: OID4VciExpectation? = nil,
                                      on coordinator: AppCoordinator) async {
        // Whether a tx_code was entered — used only to decide whether to change the failure wording to TXC-E-01 (catch below).
        var enteredTxCode = false
        do {
            OverlayManager.shared.showLoading()
            let issue = try await IssueOID4VcProtocol.begin(rawPayload: qrString)

            if let expecting {
                try issue.validate(expectedIssuer: expecting.issuer,
                                   configurationId: expecting.configurationId)
            }

            // v1 supports only pre-authorized_code.
            guard issue.isPreAuthorized else {
                OverlayManager.shared.hideLoading()
                OverlayManager.shared.showPopup(
                    title: "Notification",
                    message: "This issuance type is not supported yet.",
                    primaryButtonTitle: "OK"
                )
                return
            }
            OverlayManager.shared.hideLoading()

            // Input modal only if the offer specifies a tx_code — length/description injected from the offer metadata.
            // If not required, leave it nil (passing an empty string would put `tx_code=` in the token request).
            // WebView issuance always takes this path, since the server creates a Pre-Authorized Code without tx_code.
            let pinCode: String?
            if let txCode = issue.txCode {
                // tx_code supports numeric only (number pad input). An unspecified input_mode is treated as the OID4VCI default, numeric.
                // For text or other non-numeric modes there is no input means, so issuance is aborted (numeric-only per server contract).
                if let mode = txCode.inputMode, mode.lowercased() != "numeric" {
                    OverlayManager.shared.showPopup(
                        title: "Notification",
                        message: "This issuance requires a non-numeric code, which isn't supported.",
                        primaryButtonTitle: "OK"
                    )
                    return
                }
                guard let entered = await coordinator.presentTxCode(
                    length: txCode.length ?? 6,
                    description: txCode.description ?? ""
                ) else { return }
                pinCode = entered
                enteredTxCode = true
            } else {
                pinCode = nil
            }

            // Token request — done before holder auth (TXC-B-01: once code entry ends, go straight to the token step).
            // If the tx_code is wrong it fails here and ends in an error dialog without PIN entry (TXC-E-01).
            OverlayManager.shared.showLoading()
            try await issue.requestToken(txCode: pinCode)
            OverlayManager.shared.hideLoading()

            // Holder key auth — PIN directly if there is no bio key, otherwise the auth method selection sheet appears.
            // The selection result (passcode) decides the issuance proof signing key: PIN→#pin key, BIO→#bio key
            // (SDK requestCredential: password != nil ? "pin" : "bio"). This is a holder identity check step separate from
            // tx_code (the issuer transaction code). Cancelling here discards the received token.
            guard let auth = await coordinator.presentAuth() else { return }

            OverlayManager.shared.showLoading()
            defer { OverlayManager.shared.hideLoading() }

            // The return value is the id of the SD-JWT stored in the wallet — the card is found by this id in the reloaded list
            // to decide the title (same name as list/detail). The SD-JWT store is separate from W3C, but
            // loadCredentials reads both together, so the new card shows up as is.
            let credentialId = try await issue.requestCredential(passcode: auth.passcode)
            await coordinator.completeIssuance(vcId: credentialId)
        } catch IssueOID4VcError.tokenRequestFailed(let underlying) {
            // TXC-E-01 — the tx_code check applies **only at the token request step**. If the response has an error message,
            // show it (COM-04); only when there is no message, substitute "Wrong code.".
            // The TX Code screen already closed when the code was handed over, so the dialog appears over the calling
            // screen (Certs) — no inline error is left on the input screen.
            coordinator.failIssuance(underlying, fallback: enteredTxCode ? "Wrong code." : nil)
        } catch {
            // Failures at other steps (metadata lookup, wallet token, credential request) are unrelated to the code.
            // Attaching "Wrong code." here would tell a user who entered it correctly that it was wrong.
            coordinator.failIssuance(error)
        }
    }

    // MARK: - OID4VCI list-based (user-initiated) issuance
    //
    // Unlike QR issuance starting from an offer, here the user first picks an Issuer/Credential from the list
    // and receives the offer via the Issuer's claim input WebView. After the offer is received it joins
    // **the same path** as QR issuance (handleOID4VCI) — there is no WebView-specific Token/Credential Request.

    /// The Issuer and Credential picked from the list — reference values for checking the completion offer (guide §8).
    struct OID4VciExpectation {
        let issuer: String
        let configurationId: String
    }

    /// Credential selection → claim input WebView → enter the existing issuance path with the completion offer.
    /// Closing the WebView or pressing Cancel on the server screen issues nothing and stays on the selection screen.
    ///
    /// Receives the Issuer the selected card belongs to and its metadata straight from the screen — multiple Issuers sit
    /// on one screen as sections, so the coordinator does not hold a "currently selected Issuer".
    static func startOID4VciWebIssuance(issuer: OID4VCIIssuerItem,
                                        metadata: IssuerMetadataResponse,
                                        configurationId: String,
                                        on coordinator: AppCoordinator) async {
        guard let userInitiationUri = issuer.userInitiationUri else { return }
        guard coordinator.canStartWebIssuance() else { return }

        let startURL: URL
        do {
            startURL = try OID4VciIssuerDirectory.startURL(
                userInitiationUri: userInitiationUri,
                configurationId: configurationId,
                did: WalletState.holderDID,
                userName: WalletState.userName,
                metadata: metadata
            )
        } catch {
            OverlayManager.shared.showErrorPopup(title: "Failed to start issuance", error: error)
            return
        }

        // Subsequent navigation is allowed only within the start URL's host (guide §11).
        guard let allowedHost = startURL.host else {
            OverlayManager.shared.showErrorPopup(
                title: "Failed to start issuance",
                error: OID4VciDirectoryError.invalidStartURL
            )
            return
        }

        // nil on close/cancel — mark only the local state as cancelled and quietly stay on the screen.
        guard let completion = await coordinator.presentOID4VciWebView(url: startURL, allowedHost: allowedHost) else {
            return
        }

        await handleOID4VCI(
            completion,
            expecting: OID4VciExpectation(
                issuer: OID4VciIssuerDirectory.expectedIssuer(
                    listed: issuer.credentialIssuer,
                    metadata: metadata
                ),
                configurationId: configurationId
            ),
            on: coordinator
        )
    }

    // MARK: - OpenDID payload branching

    /// QR issuance — IssueOfferPayload → auth → issuance handshake → success screen.
    private static func issueFromQR(data: Data, on coordinator: AppCoordinator) async {
        do {
            let offer = try IssueOfferPayload(from: data)
            print("▶️[QR-ISSUE]◀️ offer.vcPlanId=\(offer.vcPlanId) issuer=\(offer.issuer) offerId=\(offer.offerId ?? "nil") type=\(offer.type)")
            guard let auth = await coordinator.presentAuth() else { return }

            OverlayManager.shared.showLoading()
            defer { OverlayManager.shared.hideLoading() }
            let vcId = try await IssueVcProtocol.issue(offer: offer, passcode: auth.passcode)
            await coordinator.completeIssuance(vcId: vcId)
        } catch {
            coordinator.failIssuance(error)
        }
    }

    /// QR presentation — branches regular VP / ZKP VP by VerifyOfferPayload.type.
    private static func presentFromQR(data: Data, on coordinator: AppCoordinator) async {
        OverlayManager.shared.showLoading()
        defer { OverlayManager.shared.hideLoading() }
        do {
            let offer = try VerifyOfferPayload(from: data)
            print("▶️[QR-VP]◀️ offer.type=\(offer.type) offerId=\(offer.offerId) mode=\(offer.mode) endpoints=\(offer.endpoints)")
            // Same as did-ca-ios VerifyProfileViewController.viewDidLoad — only .VerifyOffer
            // is regular VP; everything else (.VerifyProofOffer, etc.) takes the ZKP path.
            if offer.type == .VerifyOffer {
                let profile = try await VerifyVcProtocol.requestProfile(offerId: offer.offerId)
                coordinator.verifyProfile = profile
                // Display data and submit plan at once. This is the only place the submit profile rules are applied, so
                // submit uses this result as is. Throws if there is no submittable card or the profile doesn't match the
                // held VCs — swallowing with try? would show an empty, unsubmittable screen with 0 documents, so
                // the failure is thrown as is to inform via an error popup and block entering the screen at all.
                coordinator.verifySummary = try await VerifyVcProtocol.presentationSummary(profile: profile)
                coordinator.push(.vpRequest)
            } else {
                let proto = VerifyZKProofProtocol()
                _ = try await proto.preProcess(offerId: offer.offerId)
                coordinator.zkpProto = proto
                coordinator.zkpAttrSelections = [:]
                coordinator.zkpReveals = []
                coordinator.zkpSelfRaws = [:]
                coordinator.push(.vpRequestZkp)
            }
        } catch is NoSubmittableCredentialError {
            Self.showNoSubmittableCredential(on: coordinator)
        } catch {
            OverlayManager.shared.showErrorPopup(title: "Failed to load presentation", error: error)
        }
    }

    /// PRES-E-04 — no submittable credential. Not holding one and 0 ACTIVE items are not distinguished in the wording.
    /// Closing with OK returns to Certs (main) — leaving it on the scan screen would show a request that can't be fulfilled again.
    private static func showNoSubmittableCredential(on coordinator: AppCoordinator) {
        OverlayManager.shared.showPopup(
            title: NoSubmittableCredentialError.title,
            message: NoSubmittableCredentialError.message,
            primaryButtonTitle: "OK",
            primaryAction: { coordinator.popToMain() }
        )
    }
}
