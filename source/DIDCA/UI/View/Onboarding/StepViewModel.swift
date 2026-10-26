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
final class StepViewModel {

    // Unlock PIN received via Yes in the Step 1 lock popup — kept until it is registered together with binding on entering Step 2.
    // It lives only in memory, so it is lost if the app terminates in between, and a resumed Step 2 binds without a lock
    // (the lock choice is not asked again). The screen and view model are recreated when the Step changes, hence static.
    private static var pendingLockPasscode: String?

    // ONB-E-04 — came back after Save in Server settings following a binding failure. Since the server changed, the Step 1
    // web view registration is redone, and after re-registration it goes to Step 2 with the previous lock choice (pendingLockPasscode), without the lock popup.
    private static var reregistering = false

    // Binding in progress — lets NEXT wait for the one started on entering Step 2 instead of starting it again.
    @ObservationIgnored private var bindingTask: Task<Bool, Never>?

    // MARK: - NEXT

    func handleNext(step: StepEnum, coordinator: AppCoordinator) {
        switch step {
        case .step1:
            handleStep1Next(coordinator: coordinator)
        case .step2:
            handleStep2Next(coordinator: coordinator)
        case .step3:
            handleStep3Next(coordinator: coordinator)
        }
    }

    // ONB-01 — opens the user registration web view. When registration finishes (ONB-03), saves userId · username and
    // shows the lock popup. Binding is not done here but on entering Step 2 (ONB-03 · ONB-E-04).
    private func handleStep1Next(coordinator: AppCoordinator) {
        // Registration is done but Unlock PIN registration was closed with X, leaving us on Step 1 — treat it as no lock
        // set and go straight to Step 2. Reopening the web view would register the same user twice (same reason as ONB-E-02).
        if Preference.getUserId() != nil, !Self.reregistering {
            Self.pendingLockPasscode = nil
            coordinator.setRoot(.onboarding(step: .step2))
            return
        }
        guard let url = URL(string: URLs.DEMO_URL + "/addUserInfo") else {
            showStepError(title: "Error", error: URLError(.badURL), coordinator: coordinator)
            return
        }
        Task {
            guard let user = await coordinator.presentUserInfoWebView(url: url) else { return }
            Preference.setUserId(user.userId)
            // On re-registration, overwrite even with an empty name so the previous server's name doesn't linger (empty reads as no name).
            Preference.setUserName(user.userName)
            if Self.reregistering {
                Self.reregistering = false
                coordinator.setRoot(.onboarding(step: .step2))
                return
            }
            showLockPopup(coordinator: coordinator)
        }
    }

    /// 02d — "Set wallet lock" popup. No → Step 2, Yes → register Unlock PIN, then Step 2.
    private func showLockPopup(coordinator: AppCoordinator) {
        OverlayManager.shared.showPopup(
            title: "Set wallet lock",
            message: "Would you like to set the Wallet for lock type?",
            primaryButtonTitle: "Yes",
            primaryAction: { self.handleLockChoice(coordinator: coordinator, setLock: true) },
            secondaryButtonTitle: "No",
            secondaryAction: { self.handleLockChoice(coordinator: coordinator, setLock: false) }
        )
    }

    // Only takes the lock choice and moves to Step 2 — no network. If Yes, the Unlock PIN is received and kept, and
    // registered together with binding on entering Step 2 (in the SDK, bindUser must come before registerLock).
    // If Unlock PIN registration is closed with X, we stay on Step 1, and subsequent NEXT goes to Step 2 without a lock.
    private func handleLockChoice(coordinator: AppCoordinator, setLock: Bool) {
        Task {
            var lockPin: String? = nil
            if setLock {
                guard let pin = await coordinator.presentPinLockRegister() else { return }
                lockPin = pin
            }
            Self.pendingLockPasscode = lockPin
            coordinator.setRoot(.onboarding(step: .step2))
        }
    }

    // MARK: - Binding (on entering Step 2)

    /// true if not yet bound. If a holder DID exists, the wallet has already passed Step 2.
    private var needsBinding: Bool {
        !Preference.isUserBound() && !WalletState.hasHolderDID
    }

    /// ONB-03 · ONB-E-04 — starts user binding right after entering Step 2. Input is blocked with loading while processing.
    /// On failure, shows a COM-02-family popup (with a Server settings link if the server was unreachable) and stays on Step 2.
    func startBindingIfNeeded(step: StepEnum, coordinator: AppCoordinator) {
        guard step == .step2, needsBinding else { return }
        _ = runBinding(coordinator: coordinator)
    }

    /// Runs binding, or returns the task if one is in progress. The result is success or not, and the failure popup is
    /// shown only once here — even if NEXT waits on the task started on entry, the popup doesn't appear twice.
    /// userId is not cleared even if binding fails — the user is already registered on the server, so clearing it would
    /// require redoing web view registration and cause a duplicate registration. The kept Unlock PIN also stays until success, for retries.
    private func runBinding(coordinator: AppCoordinator) -> Task<Bool, Never> {
        if let bindingTask { return bindingTask }
        let lockPin = Self.pendingLockPasscode
        let task = Task<Bool, Never> {
            defer { self.bindingTask = nil }
            // The failure popup (showPopup) dismisses loading, so hideLoading is only called on the success path.
            OverlayManager.shared.showLoading()
            do {
                try await UserBinder.bind(lockPasscode: lockPin)
                Preference.setUserBound(true)
                Self.pendingLockPasscode = nil
                OverlayManager.shared.hideLoading()
                return true
            } catch {
                self.showStepError(
                    title: lockPin != nil ? "Failed to set wallet lock" : "Failed to bind user",
                    error: error,
                    coordinator: coordinator,
                    onSaved: {
                        Self.reregistering = true
                        coordinator.setRoot(.onboarding(step: .step1))
                    }
                )
                return false
            }
        }
        bindingTask = task
        return task
    }

    // MARK: - Step 2

    // PIN → biometric modal → (regardless of skip/enable) create default keys + DID document in one go with a single token.
    // Key generation and createHolderDIDDocument use the same .CREATE_DID token, so
    // they are bundled to reduce the loading/network span to one.
    private func handleStep2Next(coordinator: AppCoordinator) {
        Task {
            // If binding failed on entry, retry it (runBinding handles loading and the failure popup). Signing keys
            // are created only in a bound wallet. runBinding shows the failure popup.
            if needsBinding {
                guard await runBinding(coordinator: coordinator).value else { return }
            }

            guard let pin = await coordinator.presentPinRegister() else { return }

            // Continue onboarding whether skip or enable.
            // completeBiometric doesn't close the modal (because of the PIN content swap in the settings flow) — close it here.
            _ = await coordinator.presentBiometric()
            coordinator.dismissModal()

            OverlayManager.shared.showLoading()
            defer { OverlayManager.shared.hideLoading() }
            do {
                let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .CREATE_DID)

                // Both must be included in the holder DID document, so create them before generating the document.
                try WalletKeys.generatePin(hWalletToken: hWalletToken, passcode: pin)
                try WalletKeys.generateKeyAgree(hWalletToken: hWalletToken)

                _ = try WalletAPI.shared.createHolderDIDDocument(hWalletToken: hWalletToken)
                try WalletAPI.shared.saveHolderDIDDocument()
            } catch {
                // On NEXT retry, if the holder layer created earlier (bio key/PIN key/holderDID etc.)
                // remains, duplicate creation tangles the flow. Local-only/synchronous calls, so no extra network.
                // deviceDID/CoreData (user binding on entering step2) is preserved since deleteAll=false.
                try? WalletAPI.shared.deleteWallet(deleteAll: false)
                showStepError(title: "Failed to register wallet keys",
                              error: error,
                              coordinator: coordinator)
                return
            }

            coordinator.setRoot(.onboarding(step: .step3))
        }
    }

    // MARK: - Step 3

    // Full RegUserProtocol flow. createHolderDIDDocument + saveHolderDIDDocument are completed in step2.
    // Flow: initiateUserRegistration → getSharedSecret → requestServerToken →
    //       retrieveKYC → createSignedDIDDoc → requestRegisterUser →
    //       confirmUserRegistration
    private func handleStep3Next(coordinator: AppCoordinator) {
        Task {
            // Don't close the auth screen until registration finishes — report failure on top of it (ONB-E-08).
            guard let pin = await coordinator.presentHeldPinAuth() else { return }

            OverlayManager.shared.showLoading()
            defer { OverlayManager.shared.hideLoading() }
            do {
                let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .CREATE_DID)
                let txId = try await TASConnection.initiateUserRegistration()
                let sharedSecret = try await TokenGenerator.getSharedSecret(type: .device, txId: txId)
                let hServerToken = try await TokenGenerator.requestServerToken(
                    purpose: .CREATE_DID,
                    txId: txId,
                    sharedSecret: sharedSecret
                )

                // DIDCA doesn't use AccessToken → kycToken nil, kycTxId = userId received from the registration web view
                try await TASConnection.retrieveKYC(
                    request: RetrieveKyc(
                        id: UUID().uuidString,
                        txId: txId,
                        serverToken: hServerToken,
                        kycTxId: Preference.getUserId(),
                        kycToken: nil
                    )
                )

                let signedDIDDoc = try WalletAPI.shared.createSignedDIDDoc(passcode: pin)
                let regUserResponse = try await WalletAPI.shared.requestRegisterUser(
                    tasURL: URLs.TAS_URL + "/tas/api/v1/request-register-user",
                    txId: txId,
                    hWalletToken: hWalletToken,
                    serverToken: hServerToken,
                    signedDIDDoc: signedDIDDoc
                )

                try await TASConnection.confirmUserRegistration(
                    txId: regUserResponse.txId,
                    serverToken: hServerToken
                )

                Preference.setUserRegistered(true)
                coordinator.dismissModal()
                coordinator.popToMain()
            } catch {
                showRegistrationError(error: error, coordinator: coordinator)
            }
        }
    }

    // MARK: - Error display

    /// ONB-E-04 — error during a step. If the server was unreachable (COM-02), a Server settings link is attached at
    /// the bottom, and on returning from that screen without saving, **the same popup is shown again**. Staying on the
    /// step where the error occurred is COM-05's (keep) policy, so the returned screen must not look blank with no guidance.
    /// If `onSaved` is given, it runs instead of the popup when returning via Save (binding failure → Step 1 re-registration).
    private func showStepError(title: String, error: Error, coordinator: AppCoordinator,
                               onSaved: (() -> Void)? = nil) {
        OverlayManager.shared.showErrorPopup(
            title: title,
            error: error,
            onServerSettings: {
                coordinator.presentServerURL(onReturn: { saved in
                    if saved, let onSaved {
                        onSaved()
                    } else {
                        self.showStepError(title: title, error: error, coordinator: coordinator, onSaved: onSaved)
                    }
                })
            }
        )
    }

    /// ONB-E-08 — Step 3 user registration failure. Shown on top of the auth screen (not an inline PIN error); OK closes the
    /// auth screen and returns to Step 3. Server settings closes the auth screen and goes there, and returning via Save · Back ·
    /// Cancel stays on Step 3 — tapping NEXT starts again from authentication.
    private func showRegistrationError(error: Error, coordinator: AppCoordinator) {
        OverlayManager.shared.showErrorPopup(
            title: "Failed to register user",
            error: error,
            primaryAction: { coordinator.dismissModal() },
            onServerSettings: {
                coordinator.dismissModal()
                coordinator.presentServerURL()
            }
        )
    }
}
