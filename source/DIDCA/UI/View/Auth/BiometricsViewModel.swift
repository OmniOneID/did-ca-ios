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
import DIDWalletSDK   // SDK enum for requestWalletToken(purpose: .CREATE_DID)

@Observable
final class BiometricsViewModel {

    // Enable button action. Shows loading only during the token request (iOS shows the biometric prompt).
    func enable(onSuccess: @escaping () -> Void) async {
        // Pre-check for already registered / biometrics not enrolled · unsupported · locked.
        // Block before key generation and keep the screen with only a notice dialog
        // (onSuccess not called → modal not closed).
        if let blocked = Biometrics.enrollmentBlock() {
            OverlayManager.shared.showPopup(
                title: blocked.title,
                message: blocked.message,
                primaryButtonTitle: "OK"
            )
            return
        }
        do {
            OverlayManager.shared.showLoading()
            let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .CREATE_DID)
            OverlayManager.shared.hideLoading()

            // Biometric prompt failures (cancel, failure, timeout) are thrown as BiometricError.
            try WalletKeys.generateBio(hWalletToken: hWalletToken)
            onSuccess()
        } catch let bioErr as BiometricError {
            OverlayManager.shared.hideLoading()
            OverlayManager.shared.showPopup(
                title: BiometricError.dialogTitle,
                message: bioErr.message,
                primaryButtonTitle: "OK"
            )
        } catch {
            OverlayManager.shared.hideLoading()
            OverlayManager.shared.showErrorPopup(title: "Failed to enable biometrics", error: error)
        }
    }
}
