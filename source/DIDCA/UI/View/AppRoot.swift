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

struct AppRoot: View {
    @State private var coordinator = AppCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    // Tracks whether the app actually went to .background and back. System prompts such as Face ID, camera permission,
    // Control Center and notifications only go as far as .inactive and never reach .background, so the lock must not be
    // shown on returning from them (prevents the regression where Unlock PIN wrongly appeared after BIO auth during issuance).
    @State private var didEnterBackground = false

    var body: some View {
        ZStack {
            OverlayInjector()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)

            // Top-level stages (splash · onboarding · main) are swapped; screens above them are stacked.
            // Each screen draws its own top bar (NavBar/header), so the system navigation bar is hidden.
            NavigationStack(path: $coordinator.path) {
                rootScreen
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(for: Screen.self) { screen in
                        pushed(screen)
                            .toolbar(.hidden, for: .navigationBar)
                            .navigationBarBackButtonHidden()
                    }
            }
        }
        .environment(coordinator)
        .animation(.default, value: coordinator.root)
        .fullScreenCover(isPresented: modalPresented) {
            modalContent
                .environment(coordinator)
                // Keeps the current modal alive and adds one more layer on top (settings Add Biometrics: bio → PIN).
                // It must be attached inside this cover so the screen below stays and the PIN slides up.
                .fullScreenCover(isPresented: stackedModalPresented) {
                    stackedModalContent
                        .environment(coordinator)
                }
        }
        .onOpenURL { coordinator.handleDeepLink($0) }
        // Deep links that arrive during cold launch (splash) or while locked are handled on transition to main + no modal.
        .onChange(of: coordinator.isReadyForScannedFlow) { _, ready in
            if ready { coordinator.drainPendingDeepLink() }
        }
        .onChange(of: scenePhase) { _, new in
            // Show Unlock PIN only on a real return from background. .inactive→.active transitions caused by
            // system prompts (Face ID, etc.) are ignored (skipped because didEnterBackground is false).
            switch new {
            case .background:
                didEnterBackground = true
            case .active:
                guard didEnterBackground else { return }
                didEnterBackground = false
                // Credentials may have been revoked/suspended on the server while away. Clear the status cache so
                // the next list load queries again (always, regardless of whether the lock is shown).
                CredentialStore.shared.invalidateStatusCache()
                // If already on splash, cold launch is in progress and splash.task reads up to the list → skip.
                guard coordinator.root != .splash else { return }

                guard WalletState.isLockEnabled else {
                    // With no lock, reload the list immediately to refresh badges.
                    if coordinator.root == .main {
                        Task { await coordinator.reloadCredentials() }
                    }
                    return
                }
                // If the lock is already showing (repeated background/return), don't show it again.
                if case .lockAuth = coordinator.modal { return }
                // A warm return shows only the lock immediately over the current screen, without splash.
                // Even if another modal (issuance/presentation/PIN, etc.) is open, the lock takes priority for security —
                // presentLockAuth cancels the in-progress flow and replaces the modal slot with the lock.
                // (splash is cold-launch only — handled by Splash.task.)
                // Re-fetch the list after the lock is passed — so nothing goes out to the network before authentication.
                Task {
                    await coordinator.presentLockAuth()
                    if coordinator.root == .main {
                        await coordinator.reloadCredentials()
                    }
                }
            default:
                break
            }
        }
    }

    /// Top-level stage — swap transition. There is no "back" among these three.
    @ViewBuilder
    private var rootScreen: some View {
        switch coordinator.root {
        case .splash:
            Splash()

        case .onboarding(let step):
            StepView(step: step)
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

        case .main:
            MainView()
        }
    }

    /// Screens pushed on top of main. Every back is `pop()` — goes back exactly one step, wherever it came from.
    @ViewBuilder
    private func pushed(_ screen: Screen) -> some View {
        switch screen {
        case .protocolSelect:
            ProtocolSelectView(
                onBack: { coordinator.pop() },
                onSelectOpenDID: { coordinator.push(.addCertificate) },
                onSelectOID4VCI: { coordinator.push(.oid4vciCredentialSelect) }
            )

        case .addCertificate:
            AddCertificateView(onBack: { coordinator.pop() })

        case .oid4vciCredentialSelect:
            CredentialSelectView(onBack: { coordinator.pop() })

        case .issueSuccess:
            // Issuance completion arrives by replacing the stack (setStack), so no screen is left behind it.
            IssueSuccessView(items: coordinator.issuedTitles) {
                coordinator.popToMain()
            }

        case .proximity:
            ProximityView(
                qrString: coordinator.proximity?.qrString,
                onBack: { coordinator.cancelProximity() },
                onStart: { await coordinator.startProximity() }
            )

        case .proximityRequest:
            // Proximity presentation consent — same screen as VP, and back is Reject (PRES-B-12: Certs after status 20).
            VPRequestView(
                summary: coordinator.proximitySummary,
                onBack: { Task { await coordinator.rejectProximity() } },
                onSubmit: { selected in await coordinator.submitProximity(selectedCodes: selected) }
            )

        case .vpRequest:
            // Back = Reject — return to Certs without submitting (PRES-B-12).
            VPRequestView(
                summary: coordinator.verifySummary,
                onBack: { coordinator.popToMain() },
                onSubmit: { selected in await coordinator.submitVp(selectedCodes: selected) }
            )

        case .oid4vpRequest:
            // Same screen as regular VP — only the summary source (oid4vpSummary) and submit path (submitOID4VP) differ.
            VPRequestView(
                summary: coordinator.oid4vpSummary,
                onBack: { coordinator.popToMain() },
                onSubmit: { selected in await coordinator.submitOID4VP(selectedCodes: selected) }
            )

        case .vpRequestZkp:
            VPRequestZkpView(
                onBack: { coordinator.popToMain() },
                onSubmit: { Task { await coordinator.submitZkpVp() } },
                onSelectAttribute: { key in coordinator.push(.zkpAttrSelect(key: key)) }
            )

        case .citizenshipSelect:
            CitizenshipSelectView(
                selected: coordinator.selectedCitizenship?.value,
                onBack: { coordinator.pop() },
                onSelect: { opt in
                    coordinator.selectedCitizenship = opt
                    coordinator.pop()
                }
            )

        case .zkpAttrSelect(let key):
            // attribute and predicate share the same picker screen (same as did-ca-ios's
            // `AttrSelectionViewController` being called from both sections).
            let summary = coordinator.zkpProto?.presentationSummary
            let claim = (summary?.attributes ?? []).first(where: { $0.key == key })
                ?? (summary?.predicates ?? []).first(where: { $0.key == key })
            ZkpAttrSelectView(
                label: claim?.label ?? "Select",
                availableValues: claim?.availableValues ?? [],
                selectedIndex: coordinator.zkpAttrSelections[key],
                onBack: { coordinator.pop() },
                onSelect: { index in
                    coordinator.zkpAttrSelections[key] = index
                    coordinator.pop()
                }
            )

        case .vcDetail(let cred):
            VCDetailView(
                credential: cred,
                onBack: { coordinator.pop() },
                onConfirmDelete: {
                    Task { await coordinator.revokeCredential(cred) }
                },
                onStatusRefreshed: { coordinator.applyRefreshedStatus($0, for: cred.id) }
            )

        case .menu:
            SettingsMenuView(
                did: coordinator.holderDID,
                onBack: { coordinator.pop() },
                onChangePin: { coordinator.present(.pinChange()) },
                onChangeUnlockPin: {
                    if WalletState.isLockEnabled {
                        coordinator.present(.pinChange(isLockAuth: true))
                    } else {
                        // SET-E-04: Change Unlock PIN tapped while Unlock PIN is not set.
                        OverlayManager.shared.showPopup(
                            title: "Notification",
                            message: "Unlock PIN not set.",
                            primaryButtonTitle: "OK"
                        )
                    }
                },
                onAddBiometrics: { Task { await coordinator.addBiometricsFromSettings() } },
                onResetApp: { coordinator.resetAll() },
                onServerUrl: { coordinator.presentServerURL() }
            )

        case .serverUrl(let fromSplash):
            ServerURLView(showsBack: !fromSplash, onClose: { coordinator.dismissServerURL(saved: $0) })
        }
    }

    @ViewBuilder
    private var modalContent: some View {
        switch coordinator.modal {
        case .pinRegister:
            // Business logic is handled by the caller (StepViewModel).
            // Here we only pass the PIN value through the continuation and close the modal.
            PINView(mode: .create()) { _, newPIN in
                coordinator.completePin(newPIN)
            }

        case .pinLockRegister:
            // Unlock (wallet lock) PIN registration — pass lock context so the design spec wording becomes "Set Unlock PIN".
            PINView(mode: .create(isLockAuth: true)) { _, newPIN in
                coordinator.completePin(newPIN)
            }

        case .pinChange(let isLockAuth):
            PINView(mode: .change(isLockAuth: isLockAuth)) { currentPIN, newPIN in
                Task {
                    await coordinator.completePinChange(
                        isLockAuth: isLockAuth,
                        currentPIN: currentPIN,
                        newPIN: newPIN
                    )
                }
            }

        case .biometric(let fromSettings):
            // Business logic is handled by the caller (StepViewModel, etc.).
            // Here we only pass the result through the continuation and close the modal.
            BiometricsView(
                isFromSettings: fromSettings,
                onEnable: { coordinator.completeBiometric(.enabled) },
                onSkip:   { coordinator.completeBiometric(.skipped) }
            )

        case .pinAuth(let isLockAuth):
            // Business logic after PIN auth is handled by the caller (await presentPinAuth).
            PINView(mode: .auth(isLockAuth: isLockAuth)) { currentPIN, _ in
                coordinator.completePin(currentPIN)
            }

        case .issueWebForm(let url):
            // Form completion/failure is handled by the caller (AddCertificateViewModel.pick).
            // Here we only pass the result through the continuation and close the modal.
            IssueWebFormView(url: url) { success in
                coordinator.completeIssueWebForm(success: success)
            }

        case .userInfoWebView(let url):
            // Saving the registration result and the lock popup are the caller's (StepViewModel) job.
            UserInfoWebView(
                url: url,
                onClose: { coordinator.completeUserInfoWebView(nil) },
                onRegistered: { coordinator.completeUserInfoWebView($0) },
                onServerSettings: {
                    // ONB-E-05 — no reason to return to a blank web view, so close it and go to Server URL.
                    // On return we're on Step 1, and tapping NEXT again opens the web view with the new address.
                    coordinator.completeUserInfoWebView(nil)
                    coordinator.presentServerURL()
                }
            )

        case .oid4vciWebView(let url, let allowedHost):
            // Completion redirect handling (parsing · validation · dedup) is the coordinator's; closing is the continuation's.
            OID4VciStartView(
                url: url,
                allowedHost: allowedHost,
                onClose: { coordinator.completeOID4VciWebView(nil) },
                onCompletionURI: { coordinator.handleOID4VciCompletion($0) }
            )

        case .qrScan:
            // Scan result/close is handled by the caller (await in presentQrScan).
            QrScanView(
                onScanned: { payload in coordinator.completeQrScan(payload) },
                onClose: { coordinator.completeQrScan(nil) }
            )

        case .txCode(let length, let description):
            // OID4VCI tx_code input. Result/close is handled by the caller (await in presentTxCode).
            TxCodeView(
                length: length,
                description: description,
                onClose: { coordinator.completeTxCode(nil) },
                onComplete: { code in coordinator.completeTxCode(code) }
            )

        case .authSelection:
            AuthMethodView(
                onBack: { coordinator.cancelAuthSelection() },
                onPin: { coordinator.completeAuthSelection(.pin) },
                onBiometrics: { coordinator.completeAuthSelection(.bio) }
            )

        case .lockAuth:
            // Unlock PIN auth modal. X button · swipe-down · system back all exit(0)
            // (project_unlock_pin_exit / UNLK-A-E-02).
            PINView(mode: .auth(isLockAuth: true), onClose: { exit(0) }) { _, _ in
                coordinator.completeLockAuth()
            }
            .interactiveDismissDisabled(true)

        case .none:
            EmptyView()
        }
    }

    private var modalPresented: Binding<Bool> {
        Binding(
            get: { coordinator.modal != nil },
            set: { presented in
                if !presented { coordinator.dismissModal() }
            }
        )
    }

    /// The layer placed on top — when dismissed, the modal below is left as is and only this layer ends as cancelled.
    private var stackedModalPresented: Binding<Bool> {
        Binding(
            get: { coordinator.stackedModal != nil },
            set: { presented in
                if !presented { coordinator.dismissStackedModal() }
            }
        )
    }

    /// Content of the stacked layer. Currently only settings Add Biometrics' PIN auth uses this path.
    @ViewBuilder
    private var stackedModalContent: some View {
        switch coordinator.stackedModal {
        case .pinAuth(let isLockAuth):
            PINView(mode: .auth(isLockAuth: isLockAuth)) { currentPIN, _ in
                coordinator.completePin(currentPIN)
            }

        default:
            EmptyView()
        }
    }
}

#Preview {
    AppRoot()
}
