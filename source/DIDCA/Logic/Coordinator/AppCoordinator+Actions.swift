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

// Terminal actions a screen starts with a single button — submit (VP / OID4VP / ZKP) and revoke.
// All three share the same skeleton: auth → loading → protocol call → success or error popup → back to main.
// Flows that start from a scan (entering issuance/presentation) belong to QRRouter — only the last
// step the user presses directly on screen lives here.
extension AppCoordinator {

    /// VC deletion — auth → server revocation + wallet deletion → list refresh → back to docs. Navigates to docs
    /// only on success (the card disappears from the list); on failure the card stays + error popup.
    ///
    /// W3C is revoked via `RevokeVcProtocol` (propose/request/confirm), OID4VCI-issued items (SD-JWT·mDoc) via
    /// `RevokeOID4VcProtocol` — their store is separate from the W3C `WalletAPI`, so the path differs.
    func revokeCredential(_ cred: Credential) async {
        if cred.badge == .sdJwt || cred.badge == .mDoc {
            await revokeOID4VC(cred)
            return
        }

        guard let auth = await presentAuth() else { return }
        await runDeletion {
            try await RevokeVcProtocol.revoke(vcId: cred.id, passcode: auth.passcode)
        }
    }

    /// Deletes an OID4VCI-issued item. The auth method is not chosen by the user as with W3C but is determined
    /// by the binding key fixed at issuance — #pin shows the PIN screen, #bio has no app screen and the SDK requires biometrics at signing time.
    ///
    /// If there is no issuer record (items issued before this feature) or the issuer doesn't support revocation, there is
    /// no server signature, so it is deleted locally only, without auth, as before.
    /// The same goes for an item the issuer has already revoked (a successful Status List read said INVALID) —
    /// nothing is left to revoke, so no auth is asked for (same as the Android app).
    private func revokeOID4VC(_ cred: Credential) async {
        if CredentialStore.shared.isConfirmedRevoked(credentialId: cred.id) {
            await runDeletion {
                try await RevokeOID4VcProtocol.deleteLocally(credentialId: cred.id)
            }
            return
        }
        OverlayManager.shared.showLoading()
        let route: RevokeOID4VcProtocol.Route
        do {
            route = try await RevokeOID4VcProtocol.route(credentialId: cred.id)
        } catch {
            OverlayManager.shared.hideLoading()
            OverlayManager.shared.showErrorPopup(
                title: "Failed to delete",
                error: error,
                fallback: "Failed to delete. Try again."
            )
            return
        }
        OverlayManager.shared.hideLoading()

        switch route {
        case .localOnly:
            await runDeletion {
                try await RevokeOID4VcProtocol.deleteLocally(credentialId: cred.id)
            }
        case let .server(metadata, bindingKeyId):
            guard let auth = await presentAuth(forBindingKeyIds: [bindingKeyId]) else { return }
            await runDeletion {
                try await RevokeOID4VcProtocol.revoke(
                    credentialId: cred.id,
                    metadata: metadata,
                    passcode: auth.passcode
                )
            }
        }
    }

    /// Common deletion wrap-up — run `work` while loading → list refresh → back to docs on OK of the completion dialog;
    /// error popup on failure.
    private func runDeletion(_ work: () async throws -> Void) async {
        OverlayManager.shared.showLoading()
        defer { OverlayManager.shared.hideLoading() }
        do {
            try await work()
            // Re-read the wallet to sync the list — the deleted VC (and its paired ZKP) drops out.
            credentials = await CredentialStore.shared.loadCredentials()
            // Shown over VC Detail; pressing OK goes to main.
            OverlayManager.shared.showPopup(
                title: "Certificate deleted",
                message: "The certificate has been deleted from your wallet.",
                primaryButtonTitle: "OK",
                primaryAction: { [weak self] in self?.popToMain() }
            )
        } catch {
            // Deletion failed → show the server message if any, otherwise the fallback. Card stays (no navigation).
            OverlayManager.shared.showErrorPopup(
                title: "Failed to delete",
                error: error,
                fallback: "Failed to delete. Try again."
            )
        }
    }

    /// Regular VP submit — auth → VerifyVcProtocol.submit (encrypted VP) → success popup → back to main.
    /// - parameter selectedCodes: claims the user checked in VPRequestView — credentialId → code set.
    ///   The submit targets are derived from the `verifySummary` shown on screen; VCs are not re-selected here.
    func submitVp(selectedCodes: [String: Set<String>] = [:]) async {
        guard let profile = verifyProfile, let summary = verifySummary else { return }
        // VAUTH: enforce the auth method the verifier required via process.authType.
        guard let auth = await presentAuth(for: profile.profile.profile.process.authType) else { return }

        OverlayManager.shared.showLoading()
        defer { OverlayManager.shared.hideLoading() }
        do {
            try await VerifyVcProtocol.submit(profile: profile, summary: summary,
                                              passcode: auth.passcode, selectedCodes: selectedCodes)
            OverlayManager.shared.showPopup(
                title: "Submission successful",
                message: "Your information has been shared successfully.",
                primaryButtonTitle: "Done",
                primaryAction: { [weak self] in self?.popToMain() }
            )
        } catch {
            // Submit failed → back to Certs (Docs) on OK.
            // The design spec gives no title; "Error" matches the Android app.
            OverlayManager.shared.showErrorPopup(
                title: "Error",
                error: error,
                primaryAction: { [weak self] in self?.popToMain() }
            )
        }
    }

    /// OID4VP submit — auth → OID4VPPresenter.submit (vp_token POST) → success popup → back to main.
    ///
    /// The auth method is decided not by the verifier but by the **binding key set at issuance of the items being submitted**. The OID4VP authorization
    /// request has no verifier authType, and SD-JWT is signed only with the `kid` fixed at issuance
    /// (see `presentAuth(forBindingKeyIds:)`). The decision is based on the summary as shown on screen — display and
    /// submit use the same matching result, so the targets cannot diverge.
    /// - parameter selectedCodes: claims the user consented to disclose — credentialId → code set.
    ///   Submission is narrowed to `verifier request ∩ user consent` (format-agnostic — same even if W3C DCQL claim queries are added).
    func submitOID4VP(selectedCodes: [String: Set<String>] = [:]) async {
        guard let authRequest = oid4vpRequest else { return }

        // The auth decision looks only at documents **actually submitted**. Looking at all candidates would also count
        // the bindings of cards the user didn't choose and demand the wrong auth (symptom: PIN pad appears when submitting only bio).
        // The inclusion rule is the same as `OID4VPPresenter.applyConsent` — the **one selected item** the screen sent
        // is the submit target, so only documents with a key are counted.
        let submittedKeyIds = (oid4vpSummary?.documents ?? [])
            .filter { selectedCodes[$0.credentialId] != nil }
            .compactMap(\.bindingKeyId)

        guard let auth = await presentAuth(forBindingKeyIds: submittedKeyIds) else { return }

        OverlayManager.shared.showLoading()
        defer { OverlayManager.shared.hideLoading() }
        do {
            try await OID4VPPresenter.submit(authRequest: authRequest, passcode: auth.passcode, selectedCodes: selectedCodes)
            OverlayManager.shared.showPopup(
                title: "Submission successful",
                message: "Your information has been shared successfully.",
                primaryButtonTitle: "Done",
                primaryAction: { [weak self] in self?.popToMain() }
            )
        } catch {
            // OID4VP submit failed → back to Certs (Docs) on OK.
            OverlayManager.shared.showErrorPopup(
                title: "Error",
                error: error,
                primaryAction: { [weak self] in self?.popToMain() }
            )
        }
    }

    /// ZKP VP submit — reuses the instance from the preProcess stage to submit → success popup → back to main.
    /// `createEncZKProof` has no holder DID signature, so no passcode is needed, and did-ca-ios
    /// `ZKPSubmissionViewController.submitAction` also calls it directly without an auth step — likewise no PIN
    /// auth step.
    /// selections / reveals / selfRaws are all passed through as is from the user input state held by the coordinator.
    func submitZkpVp() async {
        guard let proto = zkpProto else { return }

        OverlayManager.shared.showLoading()
        defer { OverlayManager.shared.hideLoading() }
        do {
            try await proto.submit(
                selections: zkpAttrSelections,
                reveals: zkpReveals,
                selfRaws: zkpSelfRaws
            )
            OverlayManager.shared.showPopup(
                title: "Submission successful",
                message: "Your information has been shared successfully.",
                primaryButtonTitle: "Done",
                primaryAction: { [weak self] in self?.popToMain() }
            )
        } catch {
            // ZKP submit failed → back to Certs (Docs) on OK.
            OverlayManager.shared.showErrorPopup(
                title: "Error",
                error: error,
                primaryAction: { [weak self] in self?.popToMain() }
            )
        }
    }

    // MARK: - Pre-issuance checks

    /// Web-input issuance (Open DID web form · OID4VCI user-initiation) sends the username to the server,
    /// so a wallet without a name is blocked right after target selection, before auth and the issuance request. On OK it stays on Add list.
    /// QR Credential Offer (pre-authorized code) doesn't use the username, so it is not covered.
    func canStartWebIssuance() -> Bool {
        guard WalletState.userName == nil else { return true }
        OverlayManager.shared.showPopup(
            title: "Can't issue credential",
            message: "Your wallet has no registered user name, so this credential can't be issued.",
            primaryButtonTitle: "OK"
        )
        return false
    }

    // MARK: - Post-issuance handling

    // There are three issuance entry points — list issuance (AddCertificateViewModel), QR issuance and OID4VCI (QRRouter).
    // They differ up to the protocol call, but the wrap-up is the same, so it's collected into the two below.

    /// Issuance success tail — re-reads the wallet to refresh the list and navigates to the success screen.
    ///
    /// The success screen title is **the card name found in the refreshed list**. It uses the same value as the list
    /// and detail, so the labels on the three screens don't diverge.
    ///
    /// - parameter vcId: id of the credential just issued. All three entry points receive this value as the issuance result
    ///   (W3C=`IssueVcProtocol`'s vcId, OID4VCI=the id of the stored SD-JWT). So it is never missing from
    ///   the list — if it is missing anyway, only the success screen is shown without a title (issuance itself succeeded).
    func completeIssuance(vcId: String) async {
        credentials = await CredentialStore.shared.loadCredentials()
        issuedTitles = credentials.first(where: { $0.id == vcId }).map { [$0.name] } ?? []
        setStack([.issueSuccess])
    }

    /// Issuance failure tail. Pressing OK returns to Certs (Docs).
    /// Loading is not hidden separately — `showErrorPopup` → `showPopup` already calls `hideLoading()`.
    ///
    /// - parameter fallback: wording to show instead for an error with no message in the response (`.other`).
    ///   The tx_code "Wrong code." takes this path — a server/network message takes precedence if present.
    ///
    /// The design spec gives no title for these dialogs; "Issuance failed" matches the Android app.
    func failIssuance(_ error: Error, fallback: String? = nil) {
        OverlayManager.shared.showErrorPopup(
            title: "Issuance failed",
            error: error,
            fallback: fallback,
            primaryAction: { [weak self] in self?.popToMain() }
        )
    }
}
