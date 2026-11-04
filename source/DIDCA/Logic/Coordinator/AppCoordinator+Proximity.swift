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
import MdocDevice

// Proximity presentation (ISO/IEC 18013-5) flow — QR engagement → receive request → consent screen → auth → response.
//
// Unlike QR-scan presentation (QRRouter), the starting point is a screen (ProximityView), and the reader pushes the request over BLE.
// So entry, receipt and termination are chained through a single session object (`ProximityPresenter`).
// **Every exit path goes through `endProximity()`** — there is one session per process, so without cleanup
// the next proximity presentation cannot open.
extension AppCoordinator {

    /// ProximityView entry — opens the session and shows the QR. Failures (BLE off, etc.) → popup → back to Certs.
    func startProximity() async {
        // If already open (screen re-entry), leave it as is.
        guard proximity == nil else { return }
        proximitySummary = nil
        let presenter = ProximityPresenter()
        proximity = presenter
        presenter.onEvent = { [weak self] event in
            Task { await self?.handleProximityEvent(event) }
        }
        do {
            try await presenter.start()
        } catch {
            // If back is pressed while waiting on the permission prompt / power, `cancelProximity` has already closed the session and left —
            // the error start throws then is a cancellation, not a failure. Same for a root swap (.task cancellation).
            guard isCurrent(presenter), !Task.isCancelled else { return }
            failProximity(error)
        }
    }

    /// Ignores an await that returns after `endProximity()` has passed via back/error — there is only one session,
    /// so reference identity is exactly "is this still the same flow".
    private func isCurrent(_ presenter: ProximityPresenter) -> Bool {
        proximity === presenter
    }

    /// Flow termination — cleans up the session and clears the reference. Success, failure, rejection and back all converge here.
    /// `proximitySummary` is not cleared — the consent screen remains behind the result popup, so clearing it here would
    /// turn Requesting Institution into "—" and make the card disappear. It is cleared at the next session start (`startProximity`).
    func endProximity() {
        proximity?.terminate()
        proximity = nil
    }

    /// ProximityView back — if it was waiting for the reader, just close.
    func cancelProximity() {
        endProximity()
        pop()
    }

    /// Consent screen back = Reject — sends only status 20 and returns to Certs.
    /// There is no separate screen announcing the rejection.
    func rejectProximity() async {
        await proximity?.reject()
        endProximity()
        popToMain()
    }

    /// Auth → assemble/send `DeviceResponse` → success popup → back to Certs.
    ///
    /// As with OID4VP, the auth method is decided by the **binding key set at issuance of the items being submitted** (`presentAuth(forBindingKeyIds:)`).
    /// - parameter selectedCodes: the **one selected item** VPRequestView sent — the key is the credential to submit,
    ///   the value is the out-of-request elements (OPTIONAL) the user turned on. Requested elements are always included even if absent from the value.
    func submitProximity(selectedCodes: [String: Set<String>]) async {
        guard let proximity else { return }
        let credentialIds = Set(selectedCodes.keys)
        let submittedKeyIds = (proximitySummary?.documents ?? [])
            .filter { credentialIds.contains($0.credentialId) }
            .compactMap(\.bindingKeyId)
        guard let auth = await presentAuth(forBindingKeyIds: submittedKeyIds) else { return }
        // While the PIN/biometric prompt is up, a reader departure or SDK error may have closed the session first via `failProximity`
        // — don't issue a token and sign (with one more prompt on the biometric path) for a dead session.
        guard isCurrent(proximity) else { return }

        OverlayManager.shared.showLoading()
        defer { OverlayManager.shared.hideLoading() }
        do {
            try await proximity.respond(selectedCodes: selectedCodes, passcode: auth.passcode)
            guard isCurrent(proximity) else { return }
            // It is fine to close right after `respond` returns (communication SDK API 3.3, 16:52 build onward) — `terminate()` drains the queued
            // fragments and the termination message until the peer receives them (capped at 1 second) before bringing the link down. Earlier builds
            // cut the connection immediately and the response was lost (real device: the reader received 0 bytes).
            endProximity()
            OverlayManager.shared.showPopup(
                title: "Submission successful",
                message: "Your information has been shared successfully.",
                primaryButtonTitle: "Done",
                primaryAction: { [weak self] in self?.popToMain() }
            )
        } catch {
            // A send failure also arrives once more via the SDK callback (`.failed`), so only whichever arrives first is reported.
            guard isCurrent(proximity) else { return }
            failProximity(error)
        }
    }

    // MARK: - Communication SDK events

    private func handleProximityEvent(_ event: ProximityEvent) async {
        // Drop late events from an already-closed session (e.g. a send failure already reported by the submit catch).
        guard proximity != nil else { return }
        switch event {
        case .requestReceived:
            await receiveProximityRequest()
        case .peerEnded:
            failProximity(MdocProximityError.peerDisconnected)
        case .failed(let error):
            failProximity(error)
        }
    }

    /// Request arrived — matches while showing receive progress, and moves to the consent screen if there are candidates.
    /// With 0 candidates, shows the "no submittable credential" notice and returns to Certs. Either way the reader must get a response or termination, so
    /// every failure path closes the session via `endProximity()`.
    private func receiveProximityRequest() async {
        guard let proximity else { return }
        OverlayManager.shared.showLoading()
        defer { OverlayManager.shared.hideLoading() }
        do {
            let summary = try await proximity.presentationSummary()
            // During matching (token request round trip), a reader departure / SDK error event may close the session first (the loading HUD
            // blocks touches, so it isn't back) — if so, don't raise the consent screen over a dead session.
            guard isCurrent(proximity) else { return }
            proximitySummary = summary
            push(.proximityRequest)
        } catch is NoSubmittableCredentialError {
            guard isCurrent(proximity) else { return }
            await proximity.reject()
            endProximity()
            OverlayManager.shared.showPopup(
                title: NoSubmittableCredentialError.title,
                message: NoSubmittableCredentialError.message,
                primaryButtonTitle: "OK",
                primaryAction: { [weak self] in self?.popToMain() }
            )
        } catch {
            guard isCurrent(proximity) else { return }
            failProximity(error, title: "Failed to load presentation")
        }
    }

    /// Failure termination — closes the session and shows a popup, back to Certs on OK. The same whether it's a start failure (Bluetooth off, etc.) or a session error (timeout, disconnect),
    /// and whether on the QR waiting screen or the progress/submit screen — even if it expires while waiting on QR, it does not stay on screen and reissue the QR;
    /// re-presenting is a new session by pressing Present again from Certs. Communication SDK
    /// errors would show their case names verbatim, so they are shown via `userMessage` instead. Others (wallet SDK, token) follow the existing
    /// error popup rules.
    /// The design spec gives no title for these proximity errors (bodies only); "Error" matches the Android app.
    /// It also keeps the title apart from the catch-all body "Failed to present. Try again."
    private func failProximity(_ error: Error, title: String = "Error") {
        endProximity()
        let fallback = (error as? MdocProximityError)?.userMessage
        OverlayManager.shared.showErrorPopup(
            title: title,
            error: error,
            fallback: fallback,
            primaryAction: { [weak self] in self?.popToMain() }
        )
    }
}
