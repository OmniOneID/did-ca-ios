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

import SwiftUI
import Observation
import DIDWalletSDK

/// Top-level stage — swapped whole, never stacked. There is no notion of "back" between the three.
enum Root: Hashable {
    case splash
    case onboarding(step: StepEnum)
    case main
}

/// A screen pushed on top of main — an element of the `NavigationStack` path.
/// Every screen here has `←` at the top. Screens closed with `X` go to `AppModal`, not the stack.
enum Screen: Hashable {
    /// Issuance protocol selection — picks Open DID / OID4VCI when entering via "From list".
    /// Open DID → addCertificate (current plan list), OID4VCI → oid4vciIssuerList.
    case protocolSelect
    case addCertificate
    /// OID4VCI issuance — credential selection screen with the listed providers' Issuers expanded as sections.
    /// There is no separate Issuer selection step (the screen itself is sectioned per Issuer).
    case oid4vciCredentialSelect
    case issueSuccess
    case proximity
    /// Proximity presentation consent — same screen (VPRequestView); only the summary source and submit path differ.
    case proximityRequest
    case vpRequest
    /// OID4VP presentation — same screen (VPRequestView) as regular VP; only the submit path differs.
    case oid4vpRequest
    case vpRequestZkp
    case citizenshipSelect
    /// ZKP attribute picker — takes a referent key and shows the candidate value list for that attribute.
    case zkpAttrSelect(key: String)
    case vcDetail(Credential)
    case menu
    /// Settings · Server URL. Pushed not only from Settings but also from the
    /// server-unreachable popups in Splash/Onboarding — there is one stack whatever the root.
    /// Server URL — when coming from the first-launch Splash server-settings popup, the AppBar has no back button.
    case serverUrl(fromSplash: Bool = false)
}

enum AppModal: Hashable {
    case pinRegister
    case pinLockRegister
    case pinChange(isLockAuth: Bool = false)
    case pinAuth(isLockAuth: Bool = false)
    case biometric(fromSettings: Bool)
    case authSelection
    // Issuance additional-info web form (DEMO_URL/addVcInfo). Carries the connection URL.
    case issueWebForm(URL)
    // OID4VCI user claim input WebView (Issuer user initiation). Carries the start URL and allowed hosts.
    case oid4vciWebView(url: URL, allowedHost: String)
    // Onboarding Step 1 user registration WebView (`DEMO_URL/addUserInfo`). Carries the connection URL.
    case userInfoWebView(URL)
    // QR scan modal — shared by issuance/presentation.
    case qrScan
    // OID4VCI tx_code input modal — shown when the offer requires a tx_code in pre-authorized_code issuance.
    // length/description are injected from the offer's tx_code metadata. A separate input unrelated to PIN auth (pinAuth).
    case txCode(length: Int, description: String)
    // Unlock PIN auth modal — shown right after Splash / on scenePhase background→active when isLock()==true.
    // X button, system back and swipe-down all exit(0). Split into its own case because
    // its X behavior differs from pinAuth(isLockAuth:true).
    case lockAuth
}

enum BiometricResult {
    case enabled
    case skipped
}

@Observable
final class AppCoordinator {
    var root: Root = .splash
    /// Screen stack on top of main. Bound directly to `NavigationStack(path:)`, so the user
    /// can also shrink it themselves via system back (edge swipe).
    var path: [Screen] = []
    var modal: AppModal? = nil
    /// A modal layered one more level on top — used only when it must appear while **keeping** the current modal
    /// (Settings' Add Biometrics: PIN comes up over the biometric screen, and closing PIN returns to biometrics).
    /// Lock (lockAuth) must always be topmost, so this slot is cleared first before showing it.
    var stackedModal: AppModal? = nil
    var credentials: [Credential] = []
    var pickedCred: Credential? = nil
    // Titles of the issued VCs to show on the issuance complete screen (IssueSuccessView).
    var issuedTitles: [String] = []
    var selectedCitizenship: CitizenshipOption? = nil
    // Regular VP submit — verifier profile received via requestProfile when scanning a presentation QR.
    var verifyProfile: _RequestProfile? = nil
    // Data for VPRequestView (verifier name, claims to submit). Filled in presentFromQR.
    var verifySummary: VpPresentationSummary? = nil
    // OID4VP submit — authorization request parsed by getAuthorizationRequest. Filled in handleOID4VP and
    // reused by submitOID4VP (source of createVp's nonce/challenge/responseUri).
    var oid4vpRequest: AuthorizationRequest? = nil
    // Data for the OID4VP VPRequestView (reuses the same type as regular VP's verifySummary).
    var oid4vpSummary: VpPresentationSummary? = nil
    // Proximity presentation — the session is opened on entering ProximityView (startProximity) and cleared when the flow ends (endProximity).
    // There is one session per process, so this reference is effectively "the proximity presentation in progress".
    var proximity: ProximityPresenter? = nil
    // Data for the proximity VPRequestView (reuses the same type as regular VP's verifySummary).
    var proximitySummary: VpPresentationSummary? = nil
    // ZKP VP submit — protocol instance that has completed preProcess on scanning `.VerifyProofOffer`.
    // Both screen display (presentationSummary) and submit reuse the same instance (equivalent to did-ca-ios
    // `VerifyZKProofProtocol.shared` — the state container for a single ZKP VP session).
    var zkpProto: VerifyZKProofProtocol? = nil
    // ZKP attribute / predicate picker result — referent key → selected sub-referent index.
    // Equivalent to did-ca-ios `ZKPSubmissionViewController.selectedIndexMap` (but uses the stable key
    // referent.key instead of IndexPath). Both attributes and predicates are kept in the same dictionary —
    // referent.key is unique across the two sections.
    var zkpAttrSelections: [String: Int] = [:]
    // ZKP attribute reveal toggle — set of attribute referent keys selected with eye-on.
    // Kept in the coordinator so it does not vanish when leaving the screen (equivalent to did-ca-ios `attrHiddenState`).
    var zkpReveals: Set<String> = []
    // ZKP self-attribute user input — referent key → text input value.
    // Equivalent to did-ca-ios `ZKPSubmissionViewController.selfRawMap` (Int keys → String keys).
    var zkpSelfRaws: [String: String] = [:]

    // What to run when leaving the Server URL screen via Back — decided by the caller.
    // Nothing for Settings (just pop), Splash retries initialization, Onboarding re-shows the error popup
    // (Back returns to that step and the popup is shown again).
    @ObservationIgnored private var serverURLReturn: ((_ saved: Bool) -> Void)?

    // Continuation for PIN modals that must return a value (shared by pinRegister / pinLockRegister).
    // Caller awaits present...() → AppRoot's PINView callback calls completePin.
    @ObservationIgnored private var pinContinuation: CheckedContinuation<String?, Never>?
    // If true, the PIN modal is not closed even after PIN entry completes — the caller closes it after finishing follow-up work.
    @ObservationIgnored private var holdsPinModal = false

    // Delivers the Biometric modal result (.enabled / .skipped) to the caller.
    @ObservationIgnored private var biometricContinuation: CheckedContinuation<BiometricResult, Never>?

    // Auth selection sheet (PIN / BIO) result — internal signal of presentAuthSelection.
    // If the user picks PIN it chains into presentPinAuth; if BIO, .bio is returned as is.
    @ObservationIgnored private var authSelectionContinuation: CheckedContinuation<AuthSelectionPick?, Never>?

    // Issuance web form result — true means upload complete (issuance proceeds), false means failure/cancel (issuance aborted).
    @ObservationIgnored private var issueWebFormContinuation: CheckedContinuation<Bool, Never>?

    // QR scan result — the recognized payload string, nil on cancel/close.
    @ObservationIgnored private var qrScanContinuation: CheckedContinuation<String?, Never>?

    // OID4VCI tx_code input result — the code string on completion, nil on cancel/close.
    @ObservationIgnored private var txCodeContinuation: CheckedContinuation<String?, Never>?

    // User registration WebView result — the user on registration complete, nil on close/load failure.
    @ObservationIgnored private var userInfoWebViewContinuation: CheckedContinuation<RegisteredUser?, Never>?

    // OID4VCI claim input WebView result — the completion redirect URL string, nil on cancel/close.
    @ObservationIgnored private var oid4vciWebViewContinuation: CheckedContinuation<String?, Never>?

    // Guard to process the completion redirect only once (guide §10 — prevents reprocessing from duplicate redirects,
    // rapid repeated taps, or screen re-creation). Reopened only when the WebView is kept after a validation failure.
    @ObservationIgnored private var oid4vciOfferHandling = false

    // Already-consumed Credential Offer URIs — never run issuance twice with the same offer (guide §8).
    @ObservationIgnored private var consumedOfferURIs: Set<String> = []

    // Unlock PIN auth completion — resumed on auth success; the X button does exit(0), so there is no nil/cancel case.
    @ObservationIgnored private var lockAuthContinuation: CheckedContinuation<Void, Never>?

    // MARK: - Credential list snapshot

    /// Re-reads the wallet list and reflects it on screen. Called after clearing the status cache, revocation/suspension shows on the badges.
    func reloadCredentials() async {
        credentials = await CredentialStore.shared.loadCredentials()
    }

    /// Reflects a status newly fetched on the detail screen into the list snapshot too — updates only that card without re-reading the wallet.
    /// (The list is a value snapshot taken at `loadCredentials()` time, so updating only the store cache won't change the badge.)
    func applyRefreshedStatus(_ status: CredentialStatus, for credentialId: String) {
        guard let index = credentials.firstIndex(where: { $0.id == credentialId }),
              credentials[index].status != status
        else {
            return
        }
        credentials[index] = credentials[index].with(status: status)
    }

    // MARK: - Navigation
    //
    // Separates top-level stage swaps (setRoot) from stack operations (push/pop). The previous structure
    // swapped out a whole screen, so "back" was really a jump to another screen, and therefore the system
    // could not know the transition direction either. Now back is a pop, and edge swipe works as is.

    /// Swaps the top-level stage — clears the stack (there is no "back" between splash, onboarding and main).
    func setRoot(_ newRoot: Root) {
        path.removeAll()
        root = newRoot
    }

    func push(_ screen: Screen) {
        path.append(screen)
    }

    /// One step back. Does nothing if the stack is empty (main).
    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    /// Goes all the way back to main — the equivalent of "home", e.g. returning after confirming an error popup.
    func popToMain() {
        path.removeAll()
        if root != .main {
            root = .main
        }
    }

    /// Sends to the Server URL screen. `onReturn` runs exactly once after that screen closes via Cancel/Back/Save,
    /// and receives whether it was closed via Save.
    /// - parameter fromSplash: the first-launch server-settings popup path — the screen gets no back button.
    func presentServerURL(fromSplash: Bool = false, onReturn: ((_ saved: Bool) -> Void)? = nil) {
        serverURLReturn = onReturn
        push(.serverUrl(fromSplash: fromSplash))
    }

    /// Server URL screen closed (common to Cancel/Back/Save) — pops, then runs what the caller handed over.
    func dismissServerURL(saved: Bool) {
        pop()
        let onReturn = serverURLReturn
        serverURLReturn = nil
        onReturn?(saved)
    }

    /// Replaces the stack whole — used when the previous screen has no meaning to return to, e.g. after issuance completes.
    func setStack(_ screens: [Screen]) {
        if root != .main {
            root = .main
        }
        path = screens
    }

    // MARK: - Deep links (openid4vp:// / openid-credential-offer://)

    // Holds deep links arriving via onOpenURL until ready. Processing is deferred during cold launch (splash)
    // and lock, and drained on transitioning to main + no modal. Same gating as scan entry.
    @ObservationIgnored private var pendingDeepLink: String? = AppCoordinator.uiTestPayload()

    #if DEBUG
    /// UI-test hook: launching with `-uiTestPayload <base64>` feeds the decoded string in as if it had been scanned.
    /// OpenDID payloads (a PayloadData JSON object) have no URL scheme, so a physical device has no other way to
    /// receive one without the camera. It goes through the deep-link buffer, so it starts only once the app reaches
    /// main with nothing on top — the same gating as a real deep link. Base64 keeps the JSON's quotes and braces
    /// intact through devicectl, and the raw argv is read because UserDefaults would try to parse it as a plist.
    private static func uiTestPayload() -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-uiTestPayload"),
              arguments.indices.contains(index + 1),
              let data = Data(base64Encoded: arguments[index + 1]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    #else
    private static func uiTestPayload() -> String? { nil }
    #endif

    /// State in which a scan/deep-link flow may start — main (empty stack) + no modal.
    /// (Same gating as QR scanning originally being possible only from main.)
    var isReadyForScannedFlow: Bool {
        root == .main && path.isEmpty && modal == nil
    }

    /// onOpenURL entry point — puts the deep link URL in the buffer and processes it immediately if already ready.
    func handleDeepLink(_ url: URL) {
        pendingDeepLink = url.absoluteString
        drainPendingDeepLink()
    }

    /// Takes held deep links out only when ready and feeds them into scan dispatch.
    /// Called by AppRoot on transitioning to ready (reaching docs after cold launch, unlock).
    func drainPendingDeepLink() {
        guard isReadyForScannedFlow, let link = pendingDeepLink else { return }
        pendingDeepLink = nil
        Task { await handleScannedQR(link) }
    }

    // MARK: - Holder DID cache

    // Holder DID cache — getDidDocument is a CoreData fetch + JSON decode, so calling it synchronously on every
    // body evaluation delays entering Settings. The DID is immutable after onboarding, so read it once and cache.
    @ObservationIgnored private var holderDIDCache: String?

    /// Current holder DID string (for display in Settings). Empty string if not yet created.
    var holderDID: String {
        if let holderDIDCache { return holderDIDCache }
        guard let did = WalletState.holderDID else {
            return ""   // DID not created yet — don't cache, retry on the next call.
        }
        holderDIDCache = did
        return did
    }

    // MARK: - Modals
    //
    // Everything below has the same skeleton: present…() raises the modal and awaits on a continuation,
    // then the callback of the screen shown in AppRoot calls complete…() to resume that continuation. So
    // the caller can use a modal like "a function that returns a value" (`await presentPinAuth()`).
    // The pairs (present/complete) always go together, so they are grouped by modal kind.

    func present(_ m: AppModal) {
        modal = m
    }

    // MARK: Modal — PIN entry/change

    /// PIN Lock registration modal. nil if the user cancels with X.
    func presentPinLockRegister() async -> String? {
        await presentPinModal(.pinLockRegister)
    }

    /// PIN registration modal (for signing key registration). nil if the user cancels with X.
    func presentPinRegister() async -> String? {
        await presentPinModal(.pinRegister)
    }

    /// PIN auth modal (returns the PIN when an input value is needed, e.g. for signing). nil if the user cancels with X.
    /// With `stacked: true`, it is layered on top without closing the current modal — cancelling returns to the screen below.
    func presentPinAuth(isLockAuth: Bool = false, stacked: Bool = false) async -> String? {
        await presentPinModal(.pinAuth(isLockAuth: isLockAuth), stacked: stacked)
    }

    /// PIN auth modal — does not close when input ends; only returns the PIN. The caller closes it with
    /// `dismissModal()` after finishing follow-up work. Used when a task failure must be reported over the auth screen.
    func presentHeldPinAuth() async -> String? {
        let pin = await presentPinModal(.pinAuth(), holdsOnComplete: true)
        if pin == nil { holdsPinModal = false }
        return pin
    }

    // Modal state right before the lock is shown — restored as is after auth. The lock does not "end"
    // the flow in progress; it "covers" it.
    @ObservationIgnored private var modalBeforeLock: (modal: AppModal?, stacked: AppModal?)?

    /// Unlock PIN auth modal — returns only on auth success. X button/swipe-down do exit(0) on the PINView side.
    ///
    /// An in-progress modal flow is **put on hold, not cancelled**. If the continuation is not woken,
    /// the waiting task simply stays where it is, and when the modal is restored after auth the user
    /// continues right where they were. Waking it with a cancel, as before, makes the flow misread it as
    /// "the user chose" and carry on — in onboarding step2, it treats biometrics as Skip and, behind the lock
    /// screen, finishes key generation and DID document publishing before moving on to step3.
    func presentLockAuth() async {
        if let prev = lockAuthContinuation {
            lockAuthContinuation = nil
            prev.resume()
        }
        // If called again while the lock is already up, don't overwrite the saved value (the original screen would be lost).
        if modalBeforeLock == nil {
            modalBeforeLock = (modal, stackedModal)
        }
        // For security the lock screen must cover the content immediately — suppress the fullScreenCover default slide-up
        // motion so it shows right away without a modal animation. The modal slot is replaced directly with the lock
        // without passing through nil (avoids the intermediate nil → present-while-dismissing re-show risk).
        // Remove any layered modal — otherwise the lock ends up beneath it. It is raised again on restore.
        withTransaction(Self.noAnimation) {
            stackedModal = nil
            modal = .lockAuth
        }
        await withCheckedContinuation { cont in
            lockAuthContinuation = cont
        }
    }

    /// Unlock auth success — called from the PINView onSuccess callback.
    /// Restores the modal that was up right before the lock (same as closing with nil if there was none).
    func completeLockAuth() {
        if let cont = lockAuthContinuation {
            lockAuthContinuation = nil
            cont.resume()
        }
        let restored = modalBeforeLock
        modalBeforeLock = nil
        // Suppress the dismiss motion too, symmetric with present (so content doesn't briefly show through the slide-down).
        withTransaction(Self.noAnimation) {
            modal = restored?.modal
            stackedModal = restored?.stacked
        }
    }

    /// Transaction to turn off fullScreenCover present/dismiss motion (lock screen only).
    private static var noAnimation: Transaction {
        var txn = Transaction()
        txn.disablesAnimations = true
        return txn
    }

    private func presentPinModal(_ m: AppModal, stacked: Bool = false, holdsOnComplete: Bool = false) async -> String? {
        if let prev = pinContinuation {
            pinContinuation = nil
            prev.resume(returning: nil)
        }
        holdsPinModal = holdsOnComplete
        if stacked {
            stackedModal = m
        } else {
            modal = m
        }
        return await withCheckedContinuation { cont in
            pinContinuation = cont
        }
    }

    /// PIN entry complete — continuation resume + close the modal.
    /// resume and modal=nil happen in the same frame, so the caller resumes as the dismiss starts →
    /// the caller's loading appears along with the modal slide (no gap where the list is exposed).
    /// If it is a layered PIN, only that layer is removed — the screen below stays.
    func completePin(_ pin: String) {
        if let cont = pinContinuation {
            pinContinuation = nil
            cont.resume(returning: pin)
        }
        // presentHeldPinAuth — the caller does the closing.
        if holdsPinModal { return }
        if stackedModal != nil {
            stackedModal = nil
        } else {
            modal = nil
        }
    }

    /// Handles PIN change modal completion. If isLockAuth, changes the Unlock PIN (changeLock);
    /// otherwise changes the signing PIN (changePin). Closes the modal on success, error popup on failure.
    /// (Previously the SDK was called directly inside AppRoot's PINView callback — separated from the View.)
    func completePinChange(isLockAuth: Bool, currentPIN: String, newPIN: String) async {
        if isLockAuth {
            do {
                // The canonical change API. Recovers the existing CEK with the old passcode and rewraps it with the new passcode.
                // Calling registerLock again would also work, but that creates a new CEK and requires issuing a wallet token
                // (CONFIGLOCK), so it depends on the server and also touches the global lock state (isLock).
                // changeLock does only local operations and leaves the lock state as is.
                try WalletAPI.shared.changeLock(oldPasscode: currentPIN, newPasscode: newPIN)
                showPinChanged(title: "Unlock PIN changed",
                               message: "Your Unlock PIN has been changed successfully.")
            } catch {
                OverlayManager.shared.showErrorPopup(
                    title: "Failed to change wallet lock",
                    error: error
                )
            }
        } else {
            do {
                try WalletAPI.shared.changePin(
                    id: KeyIdName.pin,
                    oldPIN: currentPIN,
                    newPIN: newPIN
                )
                showPinChanged(title: "PIN changed",
                               message: "Your PIN has been changed successfully.")
            } catch {
                OverlayManager.shared.showErrorPopup(
                    title: "Failed to change PIN",
                    error: error
                )
            }
        }
    }

    /// PIN / Unlock PIN change success notice — shown over the last PIN screen; OK closes the modal and
    /// returns to Settings. It never happens that only the popup closes and you're left on the finished PIN screen.
    private func showPinChanged(title: String, message: String) {
        OverlayManager.shared.showPopup(
            title: title,
            message: message,
            primaryButtonTitle: "OK",
            primaryAction: { [weak self] in self?.dismissModal() }
        )
    }

    // MARK: Modal — Auth gate (PIN / BIO selection)

    /// Auth step right before signing, e.g. in the issuance flow.
    /// If a biometric key is registered and LAContext is available, shows the PIN/BIO selection sheet;
    /// otherwise goes straight to the PIN auth modal.
    /// - If the user picks BIO, only `.bio` comes back without a passcode; the actual biometric prompt is
    ///   triggered by the SDK when the caller calls `WalletAPI.shared.getSignedDidAuth(passcode: nil)`.
    /// - If the user picks PIN, `.pin(passcode)` comes back after the PIN input modal.
    /// - nil if the user cancels at any step.
    func presentAuth() async -> AuthChoice? {
        let canUseBio = Biometrics.hasBioKey && Biometrics.canEvaluate()

        if !canUseBio {
            guard let pin = await presentPinAuth() else { return nil }
            beginAuthLoading()
            return .pin(pin)
        }

        guard let pick = await presentAuthSelection() else { return nil }
        switch pick {
        case .bio:
            // BIO chosen → no follow-up modal. Close the selection sheet and switch to loading.
            modal = nil
            beginAuthLoading()
            return .bio
        case .pin:
            // PIN chosen → instead of closing the selection sheet with nil, replace it directly with the PIN modal (content swap).
            // completeAuthSelection doesn't set modal to nil, so .authSelection→.pinAuth is a direct
            // transition and the PIN pad appears without present-while-dismissing.
            guard let pin = await presentPinAuth() else { return nil }
            beginAuthLoading()
            return .pin(pin)
        }
    }

    /// Right after auth (PIN/bio) success — shows loading instantly without fade in the same frame as the modal dismiss,
    /// removing the gap where the bare screen shows during the slide-down (~0.35s). The caller's (issue/submit/revoke)
    /// showLoading is then a no-op since it's already showing, and defer hideLoading cleans up → no leak.
    private func beginAuthLoading() {
        OverlayManager.shared.showLoading(animated: false)
    }

    /// For VP submit — forces the auth method branch according to the VerifyAuthType the verifier requires (PIN / BIO / PIN_OR_BIO / PIN_AND_BIO).
    /// authType nil/other → treated as no verifier requirement, uses the existing local-availability-based presentAuth().
    /// Auth unrelated to a verifier, such as issuance/revocation, keeps using the existing presentAuth().
    /// PIN_AND_BIO has no reference, so it is implemented as "PIN signature + local biometric gate" — server contract needs confirmation (best-guess).
    func presentAuth(for authType: VerifyAuthType?) async -> AuthChoice? {
        guard let authType else { return await presentAuth() }

        let needPin = authType.contains(.pin)
        let needBio = authType.contains(.bio)
        let needBoth = authType.contains(.and)

        // PIN_AND_BIO: biometric gate after PIN auth, signing uses #pin.
        if needPin && needBio && needBoth {
            if let bioErr = Biometrics.signingReadiness() {
                OverlayManager.shared.showPopup(title: BiometricError.dialogTitle, message: bioErr.message, primaryButtonTitle: "OK")
                return nil
            }
            guard let pin = await presentPinAuth() else { return nil }
            guard await Biometrics.evaluate(reason: "Authenticate to submit") else { return nil }
            beginAuthLoading()
            return .pin(pin)
        }

        // PIN_OR_BIO: both allowed → same as the local availability policy.
        // Selection sheet if bio is available; PIN directly if unregistered/unavailable (quiet fallback without an error popup).
        if needPin && needBio {
            return await presentAuth()
        }

        // BIO: biometrics directly without a sheet. Abort if biometrics are required but unregistered/unavailable.
        if needBio {
            if let bioErr = Biometrics.signingReadiness() {
                OverlayManager.shared.showPopup(title: BiometricError.dialogTitle, message: bioErr.message, primaryButtonTitle: "OK")
                return nil
            }
            beginAuthLoading()
            return .bio
        }

        // PIN: PIN directly without a sheet.
        if needPin {
            guard let pin = await presentPinAuth() else { return nil }
            beginAuthLoading()
            return .pin(pin)
        }

        // .free etc. with no specific requirement → existing behavior.
        return await presentAuth()
    }

    /// For OID4VP submit — decides the auth method by the **binding key set at issuance** of the items being submitted.
    ///
    /// For SD-JWT the user cannot choose the auth method. The SDK signs each credential with
    /// `walletCore.sign(keyId: item.kid, pin:)`, and `kid` is fixed at issuance.
    /// So no selection sheet must be shown (there is nothing to choose), and mixed bindings are no problem —
    /// Secure Enclave keys (#bio) ignore the passed passcode and the OS shows a biometric prompt at signing
    /// time, while only software keys (#pin) require the passcode. That is, **if there is even one #pin, passing just
    /// the PIN satisfies both.**
    ///
    /// - parameter bindingKeyIds: `bindingKeyId` list of the OID4VC-issued items (SD-JWT·mDoc) being submitted.
    ///   Empty if W3C only.
    /// - returns: `.pin(passcode)` / `.bio` (no app auth — handled by the SDK) / nil on cancel.
    func presentAuth(forBindingKeyIds bindingKeyIds: [String]) async -> AuthChoice? {
        // No binding keys (W3C only) → existing policy — selection sheet if there is a bio key, otherwise PIN directly.
        guard !bindingKeyIds.isEmpty else { return await presentAuth() }

        if bindingKeyIds.contains(KeyIdName.pin) {
            guard let pin = await presentPinAuth() else { return nil }
            beginAuthLoading()
            return .pin(pin)
        }

        // All bound to #bio — the app shows no screen at all. The SDK requires biometrics at signing time.
        beginAuthLoading()
        return .bio
    }

    private func presentAuthSelection() async -> AuthSelectionPick? {
        if let prev = authSelectionContinuation {
            authSelectionContinuation = nil
            prev.resume(returning: nil)
        }
        modal = .authSelection
        return await withCheckedContinuation { cont in
            authSelectionContinuation = cont
        }
    }

    /// Called from the selection sheet's button action — only resumes the continuation.
    /// Closing/replacing the modal is handled by the resumed presentAuth (.bio → modal=nil, .pin → modal=.pinAuth swap).
    /// Setting modal=nil here would cause a nil→.pinAuth re-show when .pin is chosen, and the PIN pad might not appear.
    func completeAuthSelection(_ pick: AuthSelectionPick) {
        if let cont = authSelectionContinuation {
            authSelectionContinuation = nil
            cont.resume(returning: pick)
        }
    }

    /// AuthMethodView back action — cancels the auth flow (resume the continuation with nil + close the modal).
    func cancelAuthSelection() {
        if let cont = authSelectionContinuation {
            authSelectionContinuation = nil
            cont.resume(returning: nil)
        }
        modal = nil
    }

    // MARK: Modal — Issuance additional-info web form

    /// Issuance additional-info web form modal. Returns form completion (true) / failure·cancel (false) asynchronously.
    func presentIssueWebForm(url: URL) async -> Bool {
        if let prev = issueWebFormContinuation {
            issueWebFormContinuation = nil
            prev.resume(returning: false)
        }
        modal = .issueWebForm(url)
        return await withCheckedContinuation { cont in
            issueWebFormContinuation = cont
        }
    }

    /// Finalizes the web form result (JS callback or X button) — continuation resume + close the modal.
    func completeIssueWebForm(success: Bool) {
        if let cont = issueWebFormContinuation {
            issueWebFormContinuation = nil
            cont.resume(returning: success)
        }
        modal = nil
    }

    // MARK: Modal — User registration WebView (onboarding Step 1)

    /// User registration WebView modal. The user on registration complete, nil on X/load failure.
    func presentUserInfoWebView(url: URL) async -> RegisteredUser? {
        if let prev = userInfoWebViewContinuation {
            userInfoWebViewContinuation = nil
            prev.resume(returning: nil)
        }
        modal = .userInfoWebView(url)
        return await withCheckedContinuation { cont in
            userInfoWebViewContinuation = cont
        }
    }

    /// Finalizes the registration WebView result — continuation resume + close the modal.
    func completeUserInfoWebView(_ user: RegisteredUser?) {
        if let cont = userInfoWebViewContinuation {
            userInfoWebViewContinuation = nil
            cont.resume(returning: user)
        }
        modal = nil
    }

    // MARK: Modal — QR scan

    /// QR scan modal. Returns the recognized payload / nil on cancel·close asynchronously.
    func presentQrScan() async -> String? {
        if let prev = qrScanContinuation {
            qrScanContinuation = nil
            prev.resume(returning: nil)
        }
        modal = .qrScan
        return await withCheckedContinuation { cont in
            qrScanContinuation = cont
        }
    }

    /// Finalizes the QR scan result (recognized payload / nil on close·cancel) — continuation resume + close the modal.
    func completeQrScan(_ payload: String?) {
        if let cont = qrScanContinuation {
            qrScanContinuation = nil
            cont.resume(returning: payload)
        }
        modal = nil
    }

    // MARK: Modal — OID4VCI tx_code input

    /// OID4VCI tx_code input modal. Returns the entered code / nil on cancel·close asynchronously.
    func presentTxCode(length: Int, description: String) async -> String? {
        if let prev = txCodeContinuation {
            txCodeContinuation = nil
            prev.resume(returning: nil)
        }
        modal = .txCode(length: length, description: description)
        return await withCheckedContinuation { cont in
            txCodeContinuation = cont
        }
    }

    /// Finalizes the tx_code input result (entered code / nil on close·cancel) — continuation resume + close the modal.
    func completeTxCode(_ code: String?) {
        if let cont = txCodeContinuation {
            txCodeContinuation = nil
            cont.resume(returning: code)
        }
        modal = nil
    }

    // MARK: Modal — OID4VCI claim input WebView

    /// OID4VCI claim input WebView modal. Returns the completion redirect URL string / nil on cancel·close.
    func presentOID4VciWebView(url: URL, allowedHost: String) async -> String? {
        if let prev = oid4vciWebViewContinuation {
            oid4vciWebViewContinuation = nil
            prev.resume(returning: nil)
        }
        oid4vciOfferHandling = false
        modal = .oid4vciWebView(url: url, allowedHost: allowedHost)
        return await withCheckedContinuation { cont in
            oid4vciWebViewContinuation = cont
        }
    }

    /// Called when the WebView intercepts an `openid-credential-offer://` navigation (guide §7·§10).
    ///
    /// `WebView` has already stopped the navigation. Here it proceeds: block duplicate handling → extract/validate the
    /// offer URI → check single consumption → end the modal. **If validation fails, the WebView is not closed** —
    /// it only reports the error and lets the user retry on the screen or close with X.
    func handleOID4VciCompletion(_ url: URL) {
        guard !oid4vciOfferHandling else { return }
        oid4vciOfferHandling = true
        do {
            let offerURI = try OID4VciIssuerDirectory.credentialOfferURI(from: url)
            guard !consumedOfferURIs.contains(offerURI) else {
                throw OID4VciDirectoryError.offerAlreadyConsumed
            }
            consumedOfferURIs.insert(offerURI)
            completeOID4VciWebView(url.absoluteString)
        } catch {
            oid4vciOfferHandling = false
            OverlayManager.shared.showErrorPopup(title: "Failed to receive credential offer", error: error)
        }
    }

    /// Finalizes the WebView result (completion redirect URL / nil on close·cancel) — continuation resume + close the modal.
    func completeOID4VciWebView(_ payload: String?) {
        if let cont = oid4vciWebViewContinuation {
            oid4vciWebViewContinuation = nil
            cont.resume(returning: payload)
        }
        modal = nil
    }

    // MARK: Modal — Biometric auth

    /// Biometric modal. Returns the result asynchronously.
    func presentBiometric(fromSettings: Bool = false) async -> BiometricResult {
        if let prev = biometricContinuation {
            biometricContinuation = nil
            prev.resume(returning: .skipped)
        }
        modal = .biometric(fromSettings: fromSettings)
        return await withCheckedContinuation { cont in
            biometricContinuation = cont
        }
    }

    /// Settings > Add Biometrics — PIN auth → confirmation screen → add bio key + update holder DID document.
    /// Unlike onboarding, the document is already published, so generateKeyPair alone does not put #bio into
    /// the server document. UpdateUserProtocol runs updateHolderDIDDocument → request/confirm-update-diddoc
    /// to add #bio to the published document. The PIN is needed to sign the document update (#pin), so it's taken first.
    func addBiometricsFromSettings() async {
        // Pre-check for already registered / unregistered·unsupported·locked —
        // blocked before PIN entry (same place as campusID).
        if let blocked = Biometrics.enrollmentBlock() {
            OverlayManager.shared.showPopup(
                title: blocked.title,
                message: blocked.message,
                primaryButtonTitle: "OK"
            )
            return
        }

        // BIO confirmation screen first (Enable=enabled / Cancel=skipped). Pressing Enable does not close that screen but
        // layers PIN **on top** — because the server accepts the document update only if signed with the #pin key.
        // Closing PIN returns to the biometric screen, so we must wait there again. Otherwise the screen is up
        // but nobody is waiting, and the Enable button goes dead.
        // Onboarding (step2) is the reverse order since PIN "registration" is the main work of that step — StepViewModel keeps it as is.
        var passcode: String?
        repeat {
            guard await presentBiometric(fromSettings: true) == .enabled else {
                dismissModal()
                return
            }
            passcode = await presentPinAuth(stacked: true)
        } while passcode == nil

        guard let pin = passcode else { return }
        // The PIN layer was already cleaned up by completePin. The biometric screen stays until registration finishes,
        // since the success notice must appear over it; on failure it is closed and then the notice shown. No key
        // has been created before reaching here (the bio key is created inside addBioKey), so there is nothing to roll back on a mid-way cancel.
        OverlayManager.shared.showLoading()
        defer { OverlayManager.shared.hideLoading() }
        do {
            try await UpdateUserProtocol.addBioKey(passcode: pin)
            // Success notice — shown over the Biometric screen; OK closes the screen and returns to Settings.
            OverlayManager.shared.showPopup(
                title: "Biometrics registered",
                message: "Biometric authentication has been set up successfully.",
                primaryButtonTitle: "OK",
                primaryAction: { [weak self] in self?.dismissModal() }
            )
        } catch let bioErr as BiometricError {
            dismissModal()
            // Biometric prompt cancelled/failed/other — notify with the design spec wording.
            OverlayManager.shared.showPopup(
                title: BiometricError.dialogTitle,
                message: bioErr.message,
                primaryButtonTitle: "OK"
            )
        } catch {
            dismissModal()
            // Server/SDK error — preserve the backend code/description.
            OverlayManager.shared.showErrorPopup(title: "Failed to enable biometrics", error: error)
        }
    }

    /// Finalizes the Biometric result (Enable/Skip button) — only resumes the continuation.
    /// Closing/replacing the modal is handled by the resumed caller (the Settings flow swaps .enabled → modal=.pinAuth,
    /// otherwise dismissModal()). Same reason as `completeAuthSelection` — setting modal=nil here would
    /// re-raise PIN after the biometric screen goes down, causing present-while-dismissing.
    func completeBiometric(_ result: BiometricResult) {
        if let cont = biometricContinuation {
            biometricContinuation = nil
            cont.resume(returning: result)
        }
    }

    // MARK: Modal — Close / continuation cleanup

    /// Does nothing while the lock is up. `presentLockAuth` first wakes waiting continuations with a cancel
    /// and then raises the lock, and the woken flows (StepViewModel.handleStep2Next,
    /// addBiometricsFromSettings) call this method on the next turn — clearing modal here would
    /// remove the lock screen just raised and open the wallet without auth. The lock ends only via completeLockAuth (auth success)
    /// or exit(0) (the release-side counterpart of the display-side "lock is always topmost" rule).
    func dismissModal() {
        guard modal != .lockAuth else { return }
        holdsPinModal = false
        stackedModal = nil
        modal = nil
        cancelPendingModalContinuations()
    }

    /// Closes only the layered modal — the modal below and its continuation are kept alive.
    /// (The path where closing PIN with X in Settings Add Biometrics returns to the biometric screen.)
    func dismissStackedModal() {
        stackedModal = nil
        if let cont = pinContinuation {
            pinContinuation = nil
            cont.resume(returning: nil)
        }
    }

    /// Resumes all waiting modal continuations with a cancel value — does not touch the modal state (`modal`).
    /// Except `lockAuthContinuation` — the lock ends only via success (complete) or exit(0).
    private func cancelPendingModalContinuations() {
        if let cont = pinContinuation {
            pinContinuation = nil
            cont.resume(returning: nil)
        }
        if let cont = biometricContinuation {
            biometricContinuation = nil
            cont.resume(returning: .skipped)
        }
        if let cont = authSelectionContinuation {
            authSelectionContinuation = nil
            cont.resume(returning: nil)
        }
        if let cont = issueWebFormContinuation {
            issueWebFormContinuation = nil
            cont.resume(returning: false)
        }
        if let cont = qrScanContinuation {
            qrScanContinuation = nil
            cont.resume(returning: nil)
        }
        if let cont = txCodeContinuation {
            txCodeContinuation = nil
            cont.resume(returning: nil)
        }
        if let cont = oid4vciWebViewContinuation {
            oid4vciWebViewContinuation = nil
            cont.resume(returning: nil)
        }
        if let cont = userInfoWebViewContinuation {
            userInfoWebViewContinuation = nil
            cont.resume(returning: nil)
        }
    }

    // MARK: - Scan / deep-link entry points
    //
    // The actual branching and flows are handled by QRRouter — only the entry points remain here
    // so screens need to know only the coordinator.

    /// Handles a scanned QR / deep link — splits OID4VP / OID4VCI / OpenDID by scheme.
    /// - parameter intent: the flow expected by the entry point that started the scan. Deep links have no entry
    ///   button, so the default `.any` does not restrict.
    func handleScannedQR(_ qrString: String, intent: ScanIntent = .any) async {
        await QRRouter.handle(qrString, intent: intent, on: self)
    }

    /// Starts list-based (user-initiated) OID4VCI issuance — receives the offer via the claim input WebView.
    func startOID4VciWebIssuance(issuer: OID4VCIIssuerItem,
                                 metadata: IssuerMetadataResponse,
                                 configurationId: String) async {
        await QRRouter.startOID4VciWebIssuance(
            issuer: issuer,
            metadata: metadata,
            configurationId: configurationId,
            on: self
        )
    }

    // MARK: - App reset

    func resetAll() {
        // Deletes the whole SDK wallet (keys, CoreData, user binding, lock) + resets the app Preference.
        // Without both, the splash bootstrap sees isExistWallet()/isUserRegistered() as true and
        // returns straight to main, so no actual reset happens.
        // (Same as deleteWallet(deleteAll: true) in did-ca-ios SplashViewController.)
        // After deletion, the splash bootstrap sees isExistWallet()==false → recreates via createWallet, and
        // with no userId routes to onboarding step1 (backend must be reachable).
        do {
            try WalletAPI.shared.deleteWallet(deleteAll: true)
        } catch {
            // Deletion failed → notify (some data may remain), abort the reset (stay in Settings).
            OverlayManager.shared.showPopup(
                title: "Notification",
                message: "Failed to reset. Try again.",
                primaryButtonTitle: "OK"
            )
            return
        }
        Preference.reset()

        holderDIDCache = nil
        credentials = []
        pickedCred = nil
        issuedTitles = []
        modal = nil
        stackedModal = nil
        // If the pre-lock modal saved at reset time remains, it would be revived by the next unlock.
        modalBeforeLock = nil
        selectedCitizenship = nil
        verifyProfile = nil
        verifySummary = nil
        oid4vpRequest = nil
        oid4vpSummary = nil
        proximitySummary = nil
        zkpProto = nil
        zkpAttrSelections = [:]
        zkpReveals = []
        zkpSelfRaws = [:]
        // The documents themselves are immutable since their versions are fixed, but leave no trace of the previous wallet's issuers.
        Task { await DIDDocumentResolver.shared.removeAll() }
        setRoot(.splash)
    }
}
