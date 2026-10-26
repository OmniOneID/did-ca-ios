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
import LocalAuthentication
import DIDWalletSDK

// Biometric availability checks and authentication. Only things that don't change wallet state live here —
// #bio key creation mutates the wallet and requires hWalletToken, so it was split out into WalletKeys.
nonisolated enum Biometrics {

    /// Classifies LAError / other errors into BIO-E. Shared by pre-checks and runtime catches.
    /// Non-LAError cases (e.g. errSecUserCanceled from a cancelled biometric prompt) are treated as BIO-E-04/05.
    static func error(from error: Error?) -> BiometricError {
        guard let code = (error as? LAError)?.code else { return .notCompleted }
        switch code {
        case .biometryNotEnrolled:                   return .notEnrolled   // BIO-E-01
        case .biometryNotAvailable, .passcodeNotSet: return .notAvailable  // BIO-E-02
        case .biometryLockout:                       return .lockedOut     // BIO-E-03
        default:                                     return .notCompleted  // BIO-E-04/05 (cancel, failure, timeout, other)
        }
    }

    /// Biometric pre-check — returns the reason (BIO-E-01/02/03) if unavailable, nil if available.
    /// Call before entering key creation/PIN entry to avoid unnecessary steps.
    static func check() -> BiometricError? {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            return nil
        }
        return self.error(from: error)
    }

    /// Yes/no check for places that don't need a reason. Even with a bio key, if the device LAContext is
    /// unavailable (Face ID not enrolled/disabled, etc.), the selection sheet is skipped and it falls back to PIN.
    static func canEvaluate() -> Bool { check() == nil }

    /// Whether the wallet has a #bio key — separate from device biometric availability (`check`).
    /// Key ownership / device availability / signing capability (`signingReadiness`) are distinct questions and aren't merged.
    static var hasBioKey: Bool {
        (try? WalletAPI.shared.isSavedKey(keyId: KeyIdName.bio)) ?? false
    }

    /// Whether biometric signing/auth is possible — the wallet has a #bio key and device biometrics are available.
    /// Returns the reason (BIO-E) if not, nil if possible. Used in VAUTH's BIO/PIN_AND_BIO cases for the
    /// "biometrics required but not enrolled → abort" decision. (No #bio key = biometrics not enrolled in wallet → .notEnrolled)
    static func signingReadiness() -> BiometricError? {
        if !hasBioKey { return .notEnrolled }
        return check()
    }

    /// Reason BIO enrollment cannot start — nil if it may start.
    /// Combines two branches into one check: already enrolled (SET-E-03) or device unavailable (BIO-E-01/02/03).
    /// Called both on entering Settings and on tapping Enable; state may change in between, so
    /// both calls are kept as is and only the check is shared.
    static func enrollmentBlock() -> String? {
        if hasBioKey { return "Biometric data is already registered on this device." }
        return check()?.message
    }

    /// Shows the biometric prompt directly and returns success/failure (for PIN_AND_BIO's biometric gate).
    static func evaluate(reason: String) async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return false }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
