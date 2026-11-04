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

// Classification of biometric enrollment failures. Messages are the design spec text verbatim.
//   Cancel/timeout and unknown/device fault share the same text in the design spec, so merged into .notCompleted.
//   The Skip/Cancel button is handled by BiometricsView, the OS prompt by the OS — no separate code.
// Classification from LAError into this type is done by Biometrics.error(from:).
enum BiometricError: Error {
    case notEnrolled
    case notAvailable
    case lockedOut
    case notCompleted   // cancel/timeout and unknown/device fault

    /// Dialog title for every biometric error message — the design spec titles these error dialogs "Error".
    static let dialogTitle = "Error"

    var message: String {
        switch self {
        case .notEnrolled:  return "No biometric data is registered."
        case .notAvailable: return "Biometric authentication is not available."
        case .lockedOut:    return "Biometric authentication is locked. Please unlock your device and try again."
        case .notCompleted: return "Biometric authentication was not completed and was not set up."
        }
    }
}
