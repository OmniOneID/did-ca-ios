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

// 생체인증 등록 실패 분류 (화면설계서 BIO-E). 메시지는 설계서 문구 그대로.
//   BIO-E-04(취소·타임아웃) 와 BIO-E-05(알수없음·기기결함) 는 설계서상 동일 문구라 .notCompleted 로 합침.
//   BIO-E-06(Skip/Cancel 버튼) 은 BiometricsView 가, BIO-E-07(OS 프롬프트) 은 OS 가 처리 — 별도 코드 없음.
// LAError → 이 타입으로의 분류는 Biometrics.error(from:) 담당.
enum BiometricError: Error {
    case notEnrolled    // BIO-E-01
    case notAvailable   // BIO-E-02
    case lockedOut      // BIO-E-03
    case notCompleted   // BIO-E-04 / BIO-E-05

    var message: String {
        switch self {
        case .notEnrolled:  return "No biometric data is registered."
        case .notAvailable: return "Biometric authentication is not available."
        case .lockedOut:    return "Biometric authentication is locked. Please unlock your device and try again."
        case .notCompleted: return "Biometric authentication was not completed and was not set up."
        }
    }
}
