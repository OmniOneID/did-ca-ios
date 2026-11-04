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

// Gathers wallet key material (#pin / #keyagree / #bio) creation in one place. The three keys pass different
// argument combinations to the SDK (passcode or not · promptMsg or not), and that difference is the key's purpose,
// so scattering them across call sites makes it easy to get the combination wrong. Key identifiers: see KeyIdName.
//
// Only creation lives here; deletion (deleteKeyPair) stays with the flows — deletion moves as one unit with
// rollback/document updates (UpdateUserProtocol), so pulling it out would actually break the context.
nonisolated enum WalletKeys {

    /// #pin — PIN signing key. Locked with the passcode; it becomes the base key for all subsequent signing/auth.
    static func generatePin(hWalletToken: String, passcode: String) throws {
        _ = try WalletAPI.shared.generateKeyPair(
            hWalletToken: hWalletToken,
            passcode: passcode,
            keyId: KeyIdName.pin,
            algType: .secp256r1
        )
    }

    /// #keyagree — for ECDH key agreement. Not a signing key, so it takes no passcode
    /// (used by TokenGenerator with the `.keyAgreement` proofPurpose).
    static func generateKeyAgree(hWalletToken: String) throws {
        _ = try WalletAPI.shared.generateKeyPair(
            hWalletToken: hWalletToken,
            keyId: KeyIdName.keyAgree,
            algType: .secp256r1
        )
    }

    /// #bio — biometric signing key. iOS shows the Face ID/Touch ID prompt at creation time, so
    /// failures such as cancellation or lockout are converted to BiometricError and thrown.
    /// (Server/SDK errors occur outside this step — handled separately by the caller's catch.)
    static func generateBio(hWalletToken: String) throws {
        do {
            _ = try WalletAPI.shared.generateKeyPair(
                hWalletToken: hWalletToken,
                keyId: KeyIdName.bio,
                algType: .secp256r1,
                promptMsg: "Authenticate to enable biometrics"
            )
        } catch {
            throw Biometrics.error(from: error)
        }
    }
}
