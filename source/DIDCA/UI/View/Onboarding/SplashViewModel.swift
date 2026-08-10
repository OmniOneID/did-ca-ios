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

    /// bootstrap 결과 라우팅 직전에 unlockAuth modal 을 한 번 띄워야 하는지 — SDK 의 `isLock()` 결과.
    var needsLockAuth: Bool = false

    func bootstrap() async -> Route? {
        async let minDelay: Void? = try? await Task.sleep(for: .seconds(0.5))

        if !WalletAPI.shared.isExistWallet() {
            let succeeded = await createWalletWithRetry()
            if !succeeded {
                // 화면 교체로 `.task` 가 취소된 것은 실패가 아니다. 앱 초기화(resetAll)처럼
                // 스택 pop 과 루트 교체가 함께 일어나면 splash 의 task 가 한 번 취소되는데,
                // 이때 URLSession 이 -999(cancelled)로 즉시 끊겨 재시도까지 순식간에 소진된다.
                // 여기서 팝업을 띄우면 다시 뜬 splash 가 정상 생성 중인데도 앱이 종료된다.
                if Task.isCancelled { return nil }
                _ = await minDelay
                // ONB-E-01: Wallet 생성 실패 → OK 시 앱 종료 (UNLK-A-E-02 의 exit(0) 와 동일 정책).
                OverlayManager.shared.showPopup(
                    title: "Initialization failed",
                    message: "Unable to create wallet.\nPlease try again later.",
                    primaryButtonTitle: "OK",
                    primaryAction: { exit(0) }
                )
                return nil
            }
        }

        _ = await minDelay

        // Wallet 존재가 보장된 시점에 한 번 lock 활성 여부를 확정한다.
        // 등록된 lock 이 없으면 SDK 가 false 를 반환하므로 isRegLock 체크 불필요.
        needsLockAuth = WalletState.isLockEnabled

        // userRegistered (step3 끝) → main.
        // userId 없음 (step1 미완 / bind 실패로 클리어됨) → step1.
        // holder DID 존재 (step2 끝) → step3.
        // 그 외 (userId 있고 키 없음) → step2.
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

    private func createWalletWithRetry() async -> Bool {
        for attempt in 1...maxCreateWalletAttempts {
            do {
                _ = try await WalletAPI.shared.createWallet(
                    tasURL: URLs.TAS_URL,
                    walletURL: URLs.WALLET_URL
                )
                return true
            } catch {
                // 실패 원인을 삼키지 않는다 — 사용자에게 보이는 문구("Unable to create wallet")는
                // 원인을 구분하지 못하므로, 서버 오류인지 로컬 키 문제인지 로그로만 가려낼 수 있다.
                print("▶️[CREATE-WALLET]◀️ attempt \(attempt)/\(maxCreateWalletAttempts) failed: "
                      + "\(error) | \(error.localizedDescription)")
                // 취소는 재시도 대상이 아니다 — 남은 시도까지 -999 로 즉시 소진될 뿐이다.
                if Task.isCancelled { return false }
                if attempt < maxCreateWalletAttempts {
                    try? await Task.sleep(for: retryBackoff)
                }
            }
        }
        return false
    }
}
