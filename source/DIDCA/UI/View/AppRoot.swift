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

    // 앱이 실제로 .background 까지 갔다 왔는지 추적. Face ID·카메라 권한·제어센터·알림 등
    // 시스템 프롬프트는 .inactive 까지만 가고 .background 엔 안 가므로, 그 복귀에는 잠금을
    // 띄우면 안 된다 (발급 시 BIO 인증 후 Unlock PIN 이 잘못 뜨던 회귀 방지).
    @State private var didEnterBackground = false

    var body: some View {
        ZStack {
            OverlayInjector()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)

            // 최상위 단계(splash·온보딩·메인)는 교체, 그 위의 화면들은 스택에 쌓인다.
            // 화면마다 자체 상단바(NavBar/header)를 그리므로 시스템 네비게이션 바는 숨긴다.
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
                // 현재 모달을 살려 둔 채 그 위에 한 겹 더 (설정 Add Biometrics 의 바이오 → PIN).
                // 이 커버 안에 붙여야 아래 화면이 남고 PIN 이 슬라이드업으로 올라온다.
                .fullScreenCover(isPresented: stackedModalPresented) {
                    stackedModalContent
                        .environment(coordinator)
                }
        }
        .onOpenURL { coordinator.handleDeepLink($0) }
        // 콜드런치(splash)·잠금 중 도착한 딥링크는, 메인+모달없음으로 전이할 때 처리.
        .onChange(of: coordinator.isReadyForScannedFlow) { _, ready in
            if ready { coordinator.drainPendingDeepLink() }
        }
        .onChange(of: scenePhase) { _, new in
            // 실제 background 복귀에만 Unlock PIN 을 띄운다. 시스템 프롬프트(Face ID 등)로
            // 인한 .inactive→.active 전이는 무시 (didEnterBackground 가 false 라 스킵).
            switch new {
            case .background:
                didEnterBackground = true
            case .active:
                guard didEnterBackground else { return }
                didEnterBackground = false
                // 자리를 비운 사이 서버에서 크리덴셜이 폐기·정지됐을 수 있다. 상태 캐시를 비워
                // 다음 목록 로딩이 다시 조회하게 한다 (잠금 표시 여부와 무관하게 항상).
                CredentialStore.shared.invalidateStatusCache()
                // 이미 splash 면 cold launch 진행 중이라 splash.task 가 목록까지 읽는다 → 스킵.
                guard coordinator.root != .splash else { return }

                guard WalletState.isLockEnabled else {
                    // 잠금이 없으면 곧바로 목록을 다시 읽어 뱃지를 갱신한다.
                    if coordinator.root == .main {
                        Task { await coordinator.reloadCredentials() }
                    }
                    return
                }
                // 이미 잠금 표시 중이면(연속 백그라운드·복귀) 재표시하지 않는다.
                if case .lockAuth = coordinator.modal { return }
                // warm 복귀는 splash 없이 현재 화면 위에 잠금만 즉시 표시.
                // 다른 모달(발급/제출/PIN 등)이 열려 있어도 보안상 잠금이 우선 —
                // presentLockAuth 가 진행 중 흐름을 취소하고 모달 슬롯을 잠금으로 교체한다.
                // (splash 는 cold launch 전용 — Splash.task 가 담당.)
                // 목록 재조회는 잠금 통과 후에 — 인증 전에 네트워크로 나가지 않게 한다.
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

    /// 최상위 단계 — 교체 전환. 이 셋 사이엔 "뒤로"가 없다.
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

    /// 메인 위에 push 되는 화면. 뒤로가기는 전부 `pop()` — 어느 화면에서 왔든 한 단계만 돌아간다.
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
            // 발급 완료는 스택을 교체해 들어오므로(setStack) 뒤에 남은 화면이 없다.
            IssueSuccessView(items: coordinator.issuedTitles) {
                coordinator.popToMain()
            }

        case .proximity:
            ProximityView(onBack: { coordinator.pop() })

        case .vpRequest:
            VPRequestView(
                summary: coordinator.verifySummary,
                onBack: { coordinator.pop() },
                onSubmit: { selected in await coordinator.submitVp(selectedCodes: selected) }
            )

        case .oid4vpRequest:
            // 일반 VP 와 같은 화면 — summary 출처(oid4vpSummary)와 제출 경로(submitOID4VP)만 다름.
            VPRequestView(
                summary: coordinator.oid4vpSummary,
                onBack: { coordinator.pop() },
                onSubmit: { selected in await coordinator.submitOID4VP(selectedCodes: selected) }
            )

        case .vpRequestZkp:
            VPRequestZkpView(
                onBack: { coordinator.pop() },
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
            // attribute 와 predicate 둘 다 같은 picker 화면을 공유 (did-ca-ios
            // `AttrSelectionViewController` 가 두 섹션에서 모두 호출되는 것과 동일).
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
                        // SET-E-04: Unlock PIN 미설정 상태에서 Change Unlock PIN 탭.
                        OverlayManager.shared.showPopup(
                            title: "Notification",
                            message: "Unlock PIN not set.",
                            primaryButtonTitle: "OK"
                        )
                    }
                },
                onAddBiometrics: { Task { await coordinator.addBiometricsFromSettings() } },
                onResetApp: { coordinator.resetAll() }
            )
        }
    }

    @ViewBuilder
    private var modalContent: some View {
        switch coordinator.modal {
        case .pinRegister:
            // 비즈니스 로직은 호출 측 (StepViewModel) 에서 처리.
            // 여기서는 PIN 값을 continuation 으로 전달하고 모달만 닫음.
            PINView(mode: .create()) { _, newPIN in
                coordinator.completePin(newPIN)
            }

        case .pinLockRegister:
            // Unlock(wallet lock) PIN 등록 — 설계서 문구가 "Set Unlock PIN" 으로 갈리도록 lock 맥락 전달.
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
            // 비즈니스 로직은 호출 측 (StepViewModel 등) 에서 처리.
            // 여기서는 결과를 continuation 으로 전달하고 모달만 닫음.
            BiometricsView(
                isFromSettings: fromSettings,
                onEnable: { coordinator.completeBiometric(.enabled) },
                onSkip:   { coordinator.completeBiometric(.skipped) }
            )

        case .pinAuth(let isLockAuth):
            // PIN 인증 후 비즈니스 로직은 호출 측에서 처리 (await presentPinAuth).
            PINView(mode: .auth(isLockAuth: isLockAuth)) { currentPIN, _ in
                coordinator.completePin(currentPIN)
            }

        case .issueWebForm(let url):
            // 폼 완료/실패는 호출 측 (AddCertificateViewModel.pick) 에서 처리.
            // 여기서는 결과를 continuation 으로 전달하고 모달만 닫음.
            IssueWebFormView(url: url) { success in
                coordinator.completeIssueWebForm(success: success)
            }

        case .oid4vciWebView(let url, let allowedHost):
            // 완료 redirect 처리(파싱·검증·중복 방지)는 코디네이터가, 닫기는 continuation 이 담당.
            OID4VciStartView(
                url: url,
                allowedHost: allowedHost,
                onClose: { coordinator.completeOID4VciWebView(nil) },
                onCompletionURI: { coordinator.handleOID4VciCompletion($0) }
            )

        case .qrScan:
            // 스캔 결과/닫기는 호출 측 (presentQrScan 의 await) 에서 처리.
            QrScanView(
                onScanned: { payload in coordinator.completeQrScan(payload) },
                onClose: { coordinator.completeQrScan(nil) }
            )

        case .txCode(let length, let description):
            // OID4VCI tx_code 입력. 결과/닫기는 호출 측 (presentTxCode 의 await) 에서 처리.
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
            // Unlock PIN 인증 모달. X 버튼·swipe-down·시스템 백 모두 exit(0)
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

    /// 위에 얹은 겹 — 내려가면 아래 모달은 그대로 두고 이 겹만 취소로 끝낸다.
    private var stackedModalPresented: Binding<Bool> {
        Binding(
            get: { coordinator.stackedModal != nil },
            set: { presented in
                if !presented { coordinator.dismissStackedModal() }
            }
        )
    }

    /// 얹은 겹의 내용. 지금은 설정 Add Biometrics 의 PIN 인증만 이 경로를 쓴다.
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
