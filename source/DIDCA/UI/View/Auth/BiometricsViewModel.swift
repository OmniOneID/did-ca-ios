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
import DIDWalletSDK   // requestWalletToken(purpose: .CREATE_DID) 의 SDK enum

@Observable
final class BiometricsViewModel {

    // Enable 버튼 액션. 토큰 요청 동안만 로딩 표시 (생체인증 prompt 는 iOS 가 띄움).
    func enable(onSuccess: @escaping () -> Void) async {
        // 이미 등록됨(SET-E-03) / 생체 미등록·미지원·잠김(BIO-E-01/02/03) 사전 점검.
        // 키 생성 전에 막고, 안내 다이얼로그만 띄운 채 화면을 유지한다
        // (onSuccess 미호출 → 모달 닫지 않음).
        if let blocked = Biometrics.enrollmentBlock() {
            OverlayManager.shared.showPopup(
                title: "Notification",
                message: blocked,
                primaryButtonTitle: "OK"
            )
            return
        }
        do {
            OverlayManager.shared.showLoading()
            let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .CREATE_DID)
            OverlayManager.shared.hideLoading()

            // 생체 prompt 실패(BIO-E-04/05)는 BiometricError 로 던져진다.
            try WalletKeys.generateBio(hWalletToken: hWalletToken)
            onSuccess()
        } catch let bioErr as BiometricError {
            OverlayManager.shared.hideLoading()
            OverlayManager.shared.showPopup(
                title: "Notification",
                message: bioErr.message,
                primaryButtonTitle: "OK"
            )
        } catch {
            OverlayManager.shared.hideLoading()
            OverlayManager.shared.showErrorPopup(title: "Failed to enable biometrics", error: error)
        }
    }
}
