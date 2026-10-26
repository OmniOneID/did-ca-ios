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
import Observation
import DIDWalletSDK

@Observable
final class SplashViewModel {
    enum Route {
        case main
        case onboarding(step: StepEnum)
    }

    private let maxCreateWalletAttempts = 3
    private let retryBackoff: Duration = .milliseconds(500)

    /// Whether the unlockAuth modal must be shown once right before routing the bootstrap result — the SDK's `isLock()` result.
    var needsLockAuth: Bool = false

    /// true while the server settings popup (SPL-01) is shown — the basis for the screen hiding its spinner.
    var isServerSetupPending: Bool = false

    /// Progress stage of the server settings popup (SPL-01). Splash's `.task` is cancelled when the Server URL screen is
    /// pushed on top and **restarts** on pop, so whether the popup was shown is remembered by the VM, not the task.
    private enum ServerSetupPhase { case notPrompted, prompting, resolved }
    private var serverSetupPhase: ServerSetupPhase = .notPrompted
    /// Tasks waiting for the popup's answer — kept as a list since the cancelled original task and the restarted one may overlap.
    private var serverSetupWaiters: [CheckedContinuation<Void, Never>] = []

    /// true after the ONB-E-01 popup is shown — its OK terminates the app, so a later restarted task doesn't rerun initialization.
    private var hasFailed: Bool = false

    /// SPL-01~03 — when onboarding isn't finished (first launch · relaunch after quitting mid-onboarding), the server
    /// settings popup is shown **before** talking to the server. Use default keeps **the saved settings as is** (SPL-02 — the
    /// build default if nothing was ever saved, otherwise the saved value; the saved value is not cleared). Server settings goes
    /// through the Server URL screen (no back) and, after returning via Save·Cancel — without showing the popup again —
    /// continues initialization with the saved value at that point. Saved values apply immediately (SRV-E-07), so the following createWallet uses the new address.
    /// Not shown once onboarding is finished (Splash → Unlock).
    ///
    /// Shown **only once** per VM. Pushing the Server URL screen makes Splash disappear and cancels `.task`;
    /// on pop, a new task calls this function again — if the answer is already in (`.resolved`) it returns
    /// immediately, and if not yet (`.prompting`) it waits for the same answer. The cancelled original task backs off via
    /// `Task.isCancelled` after receiving the answer (on the Splash side) and the restarted task continues initialization.
    func promptServerSetupIfNeeded(coordinator: AppCoordinator) async {
        guard !Preference.isUserRegistered() else { return }
        switch serverSetupPhase {
        case .resolved:
            return
        case .prompting:
            break
        case .notPrompted:
            serverSetupPhase = .prompting
            isServerSetupPending = true
            OverlayManager.shared.showPopup(
                title: "Server settings",
                message: "Continue with the default server, or set a custom server address before connecting.",
                primaryButtonTitle: "Use default",
                primaryAction: { [weak self] in self?.resolveServerSetup() },
                linkButtonTitle: "Server settings",
                linkAction: { [weak self] in
                    coordinator.presentServerURL(fromSplash: true, onReturn: { _ in self?.resolveServerSetup() })
                }
            )
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            serverSetupWaiters.append(continuation)
        }
    }

    /// The popup's answer (Use default · return from Server URL screen) — wakes up all waiting tasks.
    private func resolveServerSetup() {
        serverSetupPhase = .resolved
        isServerSetupPending = false
        let waiters = serverSetupWaiters
        serverSetupWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    /// - parameter coordinator: used by the `Server settings` link attached at the bottom of the error popup to go to
    ///   the Server URL screen when initialization ends in a **server unreachable** failure (ONB-E-01). For other causes
    ///   the link isn't attached, so it isn't used.
    func bootstrap(coordinator: AppCoordinator) async -> Route? {
        // Going back and forth to the Server URL screen while the ONB-E-01 popup is shown restarts `.task` — since that popup's OK
        // terminates the app, initialization isn't rerun here (connecting to the new address is up to the relaunched Splash).
        guard !hasFailed else { return nil }
        async let minDelay: Void? = try? await Task.sleep(for: .seconds(0.5))

        if !WalletAPI.shared.isExistWallet() {
            if let failure = await createWalletWithRetry() {
                // `.task` being cancelled by a screen swap is not a failure. When a stack pop and a root swap happen together,
                // as in app reset (resetAll), splash's task is cancelled once,
                // and URLSession is cut off immediately with -999 (cancelled), exhausting the retries in an instant.
                // Showing a popup here would terminate the app even though the re-shown splash is creating normally.
                if Task.isCancelled { return nil }
                _ = await minDelay
                showInitializationFailure(failure, coordinator: coordinator)
                return nil
            }
        }

        _ = await minDelay

        // Determine once whether lock is enabled, at the point where the Wallet is guaranteed to exist.
        // If no lock is registered the SDK returns false, so an isRegLock check is unnecessary.
        needsLockAuth = WalletState.isLockEnabled

        // userRegistered (end of step3) → main.
        // no userId (registration web view not finished) → step1.
        // holder DID exists (end of step2) → step3.
        // otherwise (userId present, no keys) → step2. This also covers quitting after registration but before binding —
        // the web view isn't shown again (ONB-E-02) and binding happens on entering Step 2. An Unlock PIN lost in between
        // isn't asked again; binding proceeds without a lock (StepViewModel).
        if Preference.isUserRegistered() {
            return .main
        }
        if Preference.getUserId() == nil {
            return .onboarding(step: .step1)
        }
        if WalletState.hasHolderDID {
            return .onboarding(step: .step3)
        }
        return .onboarding(step: .step2)
    }

    /// ONB-E-01 — Wallet creation failed. OK terminates the app (same policy as UNLK-A-E-02's exit(0)).
    ///
    /// If the server was unreachable (COM-02), a `Server settings` link is attached at the bottom, and on returning from that
    /// screen **the same popup is shown again** (ONB-E-01). The saved address applies immediately (SRV-E-07), but this popup's OK
    /// terminates the app, so reconnecting with the new address is up to the relaunched Splash.
    private func showInitializationFailure(_ error: Error, coordinator: AppCoordinator) {
        hasFailed = true
        OverlayManager.shared.showErrorPopup(
            title: "Initialization failed",
            error: error,
            fallback: "Unable to create wallet.\nPlease try again later.",
            primaryAction: { exit(0) },
            onServerSettings: {
                coordinator.presentServerURL(onReturn: { _ in
                    self.showInitializationFailure(error, coordinator: coordinator)
                })
            }
        )
    }

    /// - Returns: nil on success, the **last attempt's error** on failure. The cause is kept because the popup wording and
    ///   whether the Server settings link is shown depend on the COM-02/03/04 branch (ONB-E-01).
    private func createWalletWithRetry() async -> Error? {
        var lastError: Error?
        for attempt in 1...maxCreateWalletAttempts {
            do {
                _ = try await WalletAPI.shared.createWallet(
                    tasURL: URLs.TAS_URL,
                    walletURL: URLs.WALLET_URL
                )
                return nil
            } catch {
                lastError = error
                // Don't swallow the failure cause — the user-facing wording ("Unable to create wallet") can't
                // distinguish causes, so only the log can tell whether it was a server error or a local key problem.
                print("▶️[CREATE-WALLET]◀️ attempt \(attempt)/\(maxCreateWalletAttempts) failed: "
                      + "\(error) | \(error.localizedDescription)")
                // Cancellation isn't retried — the remaining attempts would just be exhausted immediately with -999.
                if Task.isCancelled { return error }
                if attempt < maxCreateWalletAttempts {
                    try? await Task.sleep(for: retryBackoff)
                }
            }
        }
        return lastError
    }
}
