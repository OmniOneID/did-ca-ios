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

enum UserBinder {

    /// 유저 바인딩. lockPasscode 가 주어지면 같은 토큰으로 wallet lock 도 함께 등록.
    /// (.PERSONALIZED / .PERSONALIZE_AND_CONFIGLOCK 가 purpose 로 자동 선택)
    static func bind(lockPasscode: String? = nil) async throws {
        let purpose: WalletTokenPurposeEnum = (lockPasscode == nil) ? .PERSONALIZED : .PERSONALIZE_AND_CONFIGLOCK
        let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: purpose)
        // bindUser 가 user row 를 finalEncKey="" 로 insert 하므로 반드시 registerLock 보다 먼저 호출.
        // 순서를 뒤집으면 registerLock 이 채운 finalEncKey 를 bindUser 가 덮어써 lock 키가 날아간다
        // → isRegLock()/isLock() 이 false 가 되어 cold launch·background 복귀 시 unlock 화면이 안 뜸.
        // (did-ca-ios UserRegWebViewController 와 동일하게 bindUser → registerLock 순서.)
        try WalletAPI.shared.bindUser(hWalletToken: hWalletToken)
        if let lockPasscode {
            _ = try WalletAPI.shared.registerLock(
                hWalletToken: hWalletToken,
                passcode: lockPasscode,
                isLock: true
            )
        }
    }

    static func unbind() async throws {
        let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .DEPERSONALIZED)
        try WalletAPI.shared.unbindUser(hWalletToken: hWalletToken)
    }
}
