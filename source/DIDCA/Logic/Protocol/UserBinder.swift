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

    /// User binding. If lockPasscode is given, the wallet lock is registered with the same token as well.
    /// (.PERSONALIZED / .PERSONALIZE_AND_CONFIGLOCK is chosen automatically as the purpose)
    static func bind(lockPasscode: String? = nil) async throws {
        let purpose: WalletTokenPurposeEnum = (lockPasscode == nil) ? .PERSONALIZED : .PERSONALIZE_AND_CONFIGLOCK
        let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: purpose)
        // bindUser inserts the user row with finalEncKey="", so it must be called before registerLock.
        // If the order is reversed, bindUser overwrites the finalEncKey registerLock filled in and the lock key is lost
        // → isRegLock()/isLock() become false and the unlock screen doesn't appear on cold launch or background return.
        // (Same bindUser → registerLock order as did-ca-ios UserRegWebViewController.)
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
