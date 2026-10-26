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
import MdocProximitySDK

// MARK: - Proximity presentation (ISO/IEC 18013-5)
//
// There are two SDKs. The **communication SDK** (`MdocDeviceSession`) only does QR engagement · BLE session · encryption/decryption
// and does not parse request bytes. The **wallet SDK** (`WalletAPI.matchMdocRequest` / `createDeviceResponse`)
// takes those bytes, matches them against held mDocs and builds the plaintext `DeviceResponse`. This type
// carries bytes between the two and converts them into the `VpPresentationSummary` the screen uses.
//
// There is **one session per process** (communication SDK `SessionRegistry`). Whether it finished or failed, `terminate()`
// must be called before the next session can open, so every path leaving this flow must go through `terminate()`.

/// Signals raised by the communication SDK that the app must react to.
enum ProximityEvent {
    /// The reader's `DeviceRequest` arrived — continues with matching → consent screen → response.
    case requestReceived
    /// The peer ended the session before a response was sent (BLE disconnect, reader cancel). Not the normal end after a response.
    case peerEnded
    /// Session failure — timeout · BLE unavailable · decryption failure, etc.
    case failed(MdocProximityError)
}

/// State container for one proximity presentation session. Held by the coordinator; the screen reads only `qrString`.
@Observable
final class ProximityPresenter {
    /// Raw engagement QR. Filled once `start()` finishes.
    private(set) var qrString: String?

    @ObservationIgnored var onEvent: ((ProximityEvent) -> Void)?

    @ObservationIgnored private let session: MdocDeviceSession
    @ObservationIgnored private var delegateProxy: DelegateProxy?
    /// The two byte strings given by the reader. **Do not re-encode** — rebuilding the transcript breaks the reader's
    /// `DeviceAuth` verification (communication SDK API §3.5). `sessionTranscript` is the communication SDK's
    /// `SessionTranscriptBytes` (#6.24(bstr)) as-is, and the wallet SDK (787af6c~) accepts that form as-is.
    @ObservationIgnored private var deviceRequest: Data?
    @ObservationIgnored private var sessionTranscript: Data?
    /// Original `matchMdocRequest` result — at submission, only the elements of the credentials the user picked are kept and returned as-is.
    @ObservationIgnored private var matched: [MdocRequestedDocument] = []
    /// Credential id → codes shown as OPTIONAL on screen (display order). At submission the screen's codes are filtered through this list —
    /// a code not shown on screen was not consented to, so it is not included.
    @ObservationIgnored private var consentOrder: [String: [String]] = [:]
    /// Marker so the end notification after `respond` finishes, which is the normal order, is not raised as `peerEnded`.
    @ObservationIgnored private var responded = false
    /// The app is closing on its own — state transitions triggered by `reject()`·`terminate()` are returned by the communication SDK
    /// **synchronously within the same call** (run immediately on the main queue), so without this marker our own disconnect
    /// would be raised as "peer disconnected". All callbacks after closing are dropped.
    @ObservationIgnored private var closed = false
    /// Marker to raise end/failure to the app **only once**. The communication SDK raises the peer's status 20 and State 'End'
    /// each as a `terminated` transition (didSet fires even when the same value is reassigned), so the same event arrives twice.
    @ObservationIgnored private var ended = false

    init() {
        var configuration = MdocDeviceConfiguration()
        // The auth method (mac/ecdsa) is decided by the wallet SDK in `createDeviceResponse` based on key capabilities
        // (`MdocDeviceResponse.authMethods`) — the communication SDK has no such setting (removed in the 9/15 build).
        // Settings · BLE Transfer Mode (BLE-03~05) — Both advertises both modes; a single mode advertises only that one.
        // It can only narrow, not widen (start fails if the device does not support the mode).
        configuration.bleAdvertiseMode = switch Preference.bleTransferMode {
        case .both:             .both
        case .centralClient:    .centralClient
        case .peripheralServer: .peripheralServer
        }
        // L2CAP is always offered — the wallet-side value only decides whether to publish the PSM characteristic in the GATT service
        // (engagement is unchanged); whether to actually upgrade is chosen by the reader's `l2capUpgrade`. If the reader doesn't pick it or
        // the channel doesn't come up, the communication SDK falls back to GATT in the same mode, so leaving it on loses no path.
        // (The communication SDK default is false, based on P6 measurements — GATT was faster for a 21KB response.)
        configuration.l2capUpgrade = true
        // PRES-E-09 (9/23-2 edition) — 90s waiting for reader connection, 60s waiting for consent/response. Same as the communication SDK
        // defaults, but stated explicitly since it's a design spec requirement, so we aren't dragged along by SDK default changes.
        configuration.engagementTimeout = 90
        configuration.responseTimeout = 60
        session = MdocDeviceSession(configuration: configuration)
    }

    // MARK: Session

    /// Creates the engagement and waits for the reader. The result is the raw QR.
    func start() async throws {
        let proxy = DelegateProxy(owner: self)
        delegateProxy = proxy
        session.delegate = proxy
        let payload = try await session.start(technology: .qr)
        qrString = payload.qrString
    }

    /// A response cannot be built (rejected, cancelled, not held). Sends status 20 only when the state allows, and cleans up in every case.
    func reject() async {
        closed = true
        try? await session.reject()
        session.terminate()
    }

    /// Can be called in any state. In a terminal state it only releases resources.
    func terminate() {
        closed = true
        session.terminate()
    }

    // MARK: Matching → screen

    /// Matches the incoming request against held mDocs and converts it into consent screen data.
    ///
    /// Display rules are PRES-B-10 (9/23 edition) — requested elements are REQUIRED, and elements the credential holds **outside the request**
    /// are OPTIONAL (off by default, submitted additionally when turned on). For a Full request there are no out-of-request elements, so all are REQUIRED.
    /// Elements the reader can't get filled (`missing`) are not held, so they aren't drawn; ambiguous codes (`isAmbiguous`) are
    /// also dropped from OPTIONAL since the SDK rejects their submission (06611). Cards are per credential, so when one credential
    /// matches multiple `docRequest`s its elements are merged into one card (same as OID4VP `mergeByCredential`).
    func presentationSummary() async throws -> VpPresentationSummary {
        guard let deviceRequest else {
            throw MdocProximityError.invalidState(current: "idle", attempted: "presentationSummary")
        }
        let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .LIST_VC_AND_PRESENT_VP)

        // If no docRequest has any candidate the SDK throws (06600) — convert it into the not-held notice (PRES-E-04).
        do {
            matched = try WalletAPI.shared.matchMdocRequest(hWalletToken: hWalletToken,
                                                            deviceRequest: deviceRequest)
        } catch let error as WalletCoreError where error.code == "MSDKWLT06600" {
            throw NoSubmittableCredentialError()
        }

        var orderedIds: [String] = []
        var codesByCredential: [String: Set<String>] = [:]
        for doc in matched {
            if codesByCredential[doc.credentialId] == nil {
                orderedIds.append(doc.credentialId)
                codesByCredential[doc.credentialId] = []
            }
            codesByCredential[doc.credentialId]?.formUnion(doc.claimCodes)
        }

        let stored = try WalletAPI.shared.getAllOID4VCs(hWalletToken: hWalletToken)
            .compactMap { $0 as? MdocCredentialItem }
        // Only ACTIVE ones become candidates (PRES-B-06). See `CredentialStore.submittableIds` for the decision ladder.
        let submittable = await CredentialStore.shared.submittableIds(
            among: orderedIds.compactMap { id in stored.first { $0.id == id } }
        )

        var documents: [VpPresentationDocument] = []
        consentOrder = [:]
        for id in orderedIds {
            guard submittable.contains(id), let cred = stored.first(where: { $0.id == id }) else { continue }
            let codes = codesByCredential[id] ?? []
            let claims = cred.mdoc.consentItems
                .filter { codes.contains($0.code) || !$0.isAmbiguous }
                .map { OID4VPPresenter.mdocClaim($0, requiredCodes: codes) }
            consentOrder[id] = claims.compactMap(\.code).filter { !codes.contains($0) }
            documents.append(VpPresentationDocument(
                credentialId: cred.id,
                title: MdocClaimDisplay.title(of: cred),
                claims: claims,
                requiredCodes: codes,
                bindingKeyId: cred.kid
            ))
        }
        guard !documents.isEmpty else { throw NoSubmittableCredentialError() }

        // Neither SDK provides the reader's name (readerAuth not interpreted) — fixed label. Pending reply on PRES-B-09.
        return VpPresentationSummary(verifierName: "Proximity Verifier", documents: documents)
    }

    // MARK: Response

    /// Builds and sends a `DeviceResponse` from the credentials the user picked. Once per session.
    ///
    /// Consent is expressed by **trimming and appending to** the `matchMdocRequest` result — elements of unpicked credentials
    /// are removed from the array, and out-of-request elements the user turned on (OPTIONAL) are appended after that credential's
    /// `claimCodes` using the `consentItems` codes as-is (PRES-B-10, SDK 841ba5f~). Requested elements cannot be turned off.
    /// - parameter selectedCodes: credential id → OPTIONAL codes the user turned on.
    /// - parameter passcode: the input value for PIN auth, nil for BIO (the SDK shows the biometric prompt at signing time).
    func respond(selectedCodes: [String: Set<String>], passcode: String?) async throws {
        guard let deviceRequest, let sessionTranscript else {
            throw MdocProximityError.invalidState(current: "idle", attempted: "respond")
        }
        // If one credential matches multiple docRequests, extra elements go **only on the first match** — no reason to repeat
        // the same element per document. They never overlap with requested codes (OPTIONAL = outside the union of requests).
        var pendingExtras = selectedCodes
        let selected = matched
            .filter { selectedCodes.keys.contains($0.credentialId) }
            .map { doc -> MdocRequestedDocument in
                guard let extras = pendingExtras.removeValue(forKey: doc.credentialId),
                      !extras.isEmpty else { return doc }
                // Append in display order (consentItems) to make the response deterministic.
                let ordered = (consentOrder[doc.credentialId] ?? []).filter(extras.contains)
                return MdocRequestedDocument(docRequestIndex: doc.docRequestIndex,
                                             docType: doc.docType,
                                             credentialId: doc.credentialId,
                                             claimCodes: doc.claimCodes + ordered,
                                             intentToRetain: doc.intentToRetain,
                                             missing: doc.missing)
            }
        let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .PRESENT_VP)
        let response = try WalletAPI.shared.createDeviceResponse(
            hWalletToken: hWalletToken,
            deviceRequest: deviceRequest,
            sessionTranscript: sessionTranscript,
            selected: selected,
            passcode: passcode
        )
        responded = true
        // Pass the plaintext as-is — encryption and transport are the communication SDK's job. Returns once transfer finishes (completed).
        try await session.respond(deviceResponse: response.response)
    }

    // MARK: Communication SDK callbacks

    fileprivate func received(deviceRequest: Data, sessionTranscript: Data) {
        guard !closed else { return }
        self.deviceRequest = deviceRequest
        self.sessionTranscript = sessionTranscript
        onEvent?(.requestReceived)
    }

    fileprivate func stateChanged(_ state: MdocDeviceState) {
        // `terminated` before a response means the peer disconnected (peerClosed · status 20). After a response it's a normal end.
        guard !closed, !ended else { return }
        if state == .terminated, !responded {
            ended = true
            onEvent?(.peerEnded)
        }
    }

    fileprivate func failed(_ error: MdocProximityError) {
        guard !closed, !ended else { return }
        ended = true
        onEvent?(.failed(error))
    }

    /// Communication SDK delegate. Callbacks arrive on `callbackQueue` (main by default), so hop straight onto the main actor.
    /// `MdocDeviceSession.delegate` is weak, so the presenter must hold on to the proxy.
    private final class DelegateProxy: MdocDeviceSessionDelegate {
        unowned let owner: ProximityPresenter
        init(owner: ProximityPresenter) { self.owner = owner }

        nonisolated func mdocSession(_ s: MdocDeviceSession, didChangeState state: MdocDeviceState) {
            MainActor.assumeIsolated { owner.stateChanged(state) }
        }
        nonisolated func mdocSession(_ s: MdocDeviceSession,
                                     didReceiveRequest deviceRequest: Data,
                                     sessionTranscript: Data) {
            MainActor.assumeIsolated { owner.received(deviceRequest: deviceRequest,
                                                      sessionTranscript: sessionTranscript) }
        }
        nonisolated func mdocSessionDidFinish(_ s: MdocDeviceSession) {}
        nonisolated func mdocSession(_ s: MdocDeviceSession, didFailWith error: MdocProximityError) {
            MainActor.assumeIsolated { owner.failed(error) }
        }
    }
}

// MARK: - Error messages

extension MdocProximityError {
    /// Message shown to the user. Communication SDK errors are not `LocalizedError`, so left as-is they would expose the case name.
    /// The design spec has no exception spec for proximity sessions, so these are provisional messages — pending reply.
    var userMessage: String {
        switch self {
        // Messages follow design spec PRES-E-06~09 (9/15 edition). After OK, all return to Certs — coordinator `failProximity`.
        // PRES-E-06 — does not distinguish turned-off from permission-denied; puts the remedy in one sentence.
        case .configurationRequired(.enableBluetooth), .configurationRequired(.grantPermission):
            return "Turn on Bluetooth and allow access to present in person."
        // PRES-E-07 — a hardware/OS reason the user can't fix, so no turn-on/allow guidance is added.
        case .bleUnavailable:
            return "Bluetooth is not available on this device."
        // PRES-E-08 — no common transport to advertise (result of a settings combination such as BLE Transfer Mode). No specific
        // guidance on which setting to change (same policy as BLE-E-01 — compatibility guidance belongs to the operations guide).
        case .unsupportedTransmissionTechnology:
            return "This device can't present in person with the current transfer settings."
        // PRES-E-09 — the four session errors.
        case .engagementTimeout:
            return "No verifier connected in time. Try again."
        case .peerDisconnected, .terminatedByPeer:
            return "The verifier ended the session."
        case .responseTimeout, .transferTimeout:
            return "The session timed out. Try again."
        default:
            return "Failed to present. Try again."
        }
    }
}
