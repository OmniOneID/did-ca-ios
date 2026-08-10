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

    // popup 만 즉시 띄움. 통신 (signup + bind) 은 사용자 선택 후 일괄 진행
    // 하여 로딩 노출 구간을 한 번으로 모은다.
    private func handleStep1Next(coordinator: AppCoordinator) {
        OverlayManager.shared.showPopup(
            title: "Set wallet lock",
            message: "Would you like to set the Wallet for lock type?",
            primaryButtonTitle: "Yes",
            primaryAction: { self.handleLockChoice(coordinator: coordinator, setLock: true) },
            secondaryButtonTitle: "No",
            secondaryAction: { self.handleLockChoice(coordinator: coordinator, setLock: false) }
        )
    }

    // setLock=true 면 PIN 입력 모달까지 거쳐 lockPasscode 동반 바인딩, false 면 PIN 없이 바로 바인딩.
    // bind 실패 시 userId 를 비워 "userId 있음 = step1 완료" invariant 유지.
    private func handleLockChoice(coordinator: AppCoordinator, setLock: Bool) {
        Task {
            var lockPin: String? = nil
            if setLock {
                guard let pin = await coordinator.presentPinLockRegister() else { return }
                lockPin = pin
            }
            OverlayManager.shared.showLoading()
            defer { OverlayManager.shared.hideLoading() }
            do {
                await signupIfNeeded()
                try await UserBinder.bind(lockPasscode: lockPin)
                coordinator.setRoot(.onboarding(step: .step2))
            } catch {
                Preference.clearUserId()
                OverlayManager.shared.showErrorPopup(
                    title: setLock ? "Failed to set wallet lock" : "Failed to bind user",
                    error: error
                )
            }
        }
    }

    // MARK: - Step 2

    // PIN → 생체인증 모달 → (skip/enable 무관) 한 토큰으로 기본 키 + DID 문서 일괄 생성.
    // 키 생성과 createHolderDIDDocument 가 같은 .CREATE_DID 토큰을 사용하므로
    // 묶어서 로딩/통신 구간을 한 번으로 줄인다.
    private func handleStep2Next(coordinator: AppCoordinator) {
        Task {
            guard let pin = await coordinator.presentPinRegister() else { return }

            // skip 이든 enable 이든 onboarding 계속 진행.
            // completeBiometric 은 모달을 닫지 않는다(설정 흐름의 PIN content swap 때문) — 여기서 닫는다.
            _ = await coordinator.presentBiometric()
            coordinator.dismissModal()

            OverlayManager.shared.showLoading()
            defer { OverlayManager.shared.hideLoading() }
            do {
                let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .CREATE_DID)

                // 둘 다 홀더 DID 문서에 실려야 하므로 문서 생성 전에 만든다.
                try WalletKeys.generatePin(hWalletToken: hWalletToken, passcode: pin)
                try WalletKeys.generateKeyAgree(hWalletToken: hWalletToken)

                _ = try WalletAPI.shared.createHolderDIDDocument(hWalletToken: hWalletToken)
                try WalletAPI.shared.saveHolderDIDDocument()
            } catch {
                // NEXT 재시도 시 이전에 만들어진 홀더 레이어 (바이오키/PIN키/holderDID 등) 가
                // 남아있으면 중복 생성으로 흐름이 꼬임. 로컬 전용/동기 호출이라 통신 추가 없음.
                // deviceDID/CoreData (step1 user binding) 는 deleteAll=false 라 보존.
                try? WalletAPI.shared.deleteWallet(deleteAll: false)
                OverlayManager.shared.showErrorPopup(
                    title: "Failed to register wallet keys",
                    error: error
                )
                return
            }

            coordinator.setRoot(.onboarding(step: .step3))
        }
    }

    // MARK: - Step 3

    // RegUserProtocol 전체 흐름. createHolderDIDDocument + saveHolderDIDDocument 는 step2 에서 완료.
    // 흐름: initiateUserRegistration → getSharedSecret → requestServerToken →
    //       retrieveKYC → createSignedDIDDoc → requestRegisterUser →
    //       confirmUserRegistration
    private func handleStep3Next(coordinator: AppCoordinator) {
        Task {
            guard let pin = await coordinator.presentPinAuth() else { return }

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

                // DIDCA 는 AccessToken 미사용 → kycToken nil, kycTxId = signup userId
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
                coordinator.popToMain()
            } catch {
                OverlayManager.shared.showErrorPopup(
                    title: "Failed to register user",
                    error: error
                )
            }
        }
    }

    // MARK: - Signup

    // userId 가 이미 있으면 스킵. walletId 는 SDK 의 Properties
    // (requestRegisterWallet 시점에 set) 에서 조회.
    // walletId 부재 또는 CAS 실패 시 무시.
    private func signupIfNeeded() async {
        guard Preference.getUserId() == nil else { return }
        guard let walletId = Properties.getWalletId() else { return }
        let userId = UUID().uuidString
        do {
            try await CASConnection.signup(
                request: .init(userId: userId, walletId: walletId)
            )
            Preference.setUserId(userId)
        } catch {
            // stub URL 이라 실패가 정상. userId 저장도 보류.
        }
    }
}
