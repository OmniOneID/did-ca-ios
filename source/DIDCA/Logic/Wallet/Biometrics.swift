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

// 생체인증 가용성 판정과 인증 수행. 지갑 상태를 바꾸지 않는 것만 둔다 —
// #bio 키 생성은 지갑을 변경하고 hWalletToken 을 요구하므로 WalletKeys 로 분리했다.
nonisolated enum Biometrics {

    /// LAError / 기타 에러를 BIO-E 로 분류. 사전 점검·런타임 catch 공용.
    /// LAError 가 아니면(생체 prompt 취소의 errSecUserCanceled 등) BIO-E-04/05 로 본다.
    static func error(from error: Error?) -> BiometricError {
        guard let code = (error as? LAError)?.code else { return .notCompleted }
        switch code {
        case .biometryNotEnrolled:                   return .notEnrolled   // BIO-E-01
        case .biometryNotAvailable, .passcodeNotSet: return .notAvailable  // BIO-E-02
        case .biometryLockout:                       return .lockedOut     // BIO-E-03
        default:                                     return .notCompleted  // BIO-E-04/05 (취소·실패·타임아웃·기타)
        }
    }

    /// 생체인증 사전 점검 — 불가하면 사유(BIO-E-01/02/03) 반환, 가능하면 nil.
    /// 키 생성/PIN 입력에 들어가기 전에 호출해 불필요한 단계를 막는다.
    static func check() -> BiometricError? {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            return nil
        }
        return self.error(from: error)
    }

    /// 사유가 필요 없는 자리에서 쓰는 가부 판정. 바이오 키가 있어도 디바이스 LAContext 가
    /// 사용 불가(FaceID 미등록/비활성 등) 면 선택 시트를 띄우지 않고 PIN 으로 fallback 한다.
    static func canEvaluate() -> Bool { check() == nil }

    /// 지갑에 #bio 키가 있는지 — 디바이스 생체 가용성(`check`)과는 별개다.
    /// 키 보유 / 디바이스 가용 / 서명 가능(`signingReadiness`)은 서로 다른 질문이라 합치지 않는다.
    static var hasBioKey: Bool {
        (try? WalletAPI.shared.isSavedKey(keyId: KeyIdName.bio)) ?? false
    }

    /// 생체로 서명/인증할 수 있는 상태인지 — 지갑에 #bio 키가 있고 디바이스 생체가 가용한지.
    /// 불가 시 사유(BIO-E) 반환, 가능하면 nil. VAUTH 의 BIO/PIN_AND_BIO 케이스에서
    /// "생체 필수인데 미등록 → 중단" 판정에 쓴다. (#bio 키 없음 = 지갑에 생체 미등록 → .notEnrolled)
    static func signingReadiness() -> BiometricError? {
        if !hasBioKey { return .notEnrolled }
        return check()
    }

    /// BIO 등록을 시작할 수 없는 사유 — 시작해도 되면 nil.
    /// 이미 등록됨(SET-E-03) 또는 디바이스 불가(BIO-E-01/02/03) 두 갈래를 한 판정으로 묶는다.
    /// 설정 진입 시점과 Enable 버튼 시점 양쪽에서 부르는데, 그 사이에 상태가 바뀔 수 있어
    /// 호출은 두 번 그대로 두고 판정만 공유한다.
    static func enrollmentBlock() -> String? {
        if hasBioKey { return "Biometric data is already registered on this device." }
        return check()?.message
    }

    /// 생체 인증 prompt 를 직접 띄워 성공/실패를 반환 (PIN_AND_BIO 의 생체 게이트용).
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
