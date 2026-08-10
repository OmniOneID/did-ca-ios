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

// 지갑 키 자료(#pin / #keyagree / #bio) 생성을 한 곳에 모은다. 세 키가 SDK 에 넘기는
// 인자 조합이 서로 다르고(passcode 유무 · promptMsg 유무) 그 차이가 곧 키의 용도라,
// 호출처에 흩어지면 조합을 틀리기 쉽다. 키 식별자는 KeyIdName 참조.
//
// 생성만 여기 모으고 삭제(deleteKeyPair)는 흐름 쪽에 남긴다 — 삭제는 롤백/문서 갱신과
// 한 덩어리로 움직여서(UpdateUserProtocol) 떼어내면 오히려 맥락이 끊긴다.
nonisolated enum WalletKeys {

    /// #pin — PIN 서명키. passcode 로 잠그며 이후 모든 서명/인증의 기준 키가 된다.
    static func generatePin(hWalletToken: String, passcode: String) throws {
        _ = try WalletAPI.shared.generateKeyPair(
            hWalletToken: hWalletToken,
            passcode: passcode,
            keyId: KeyIdName.pin,
            algType: .secp256r1
        )
    }

    /// #keyagree — ECDH 키 합의용. 서명키가 아니라서 passcode 를 받지 않는다
    /// (TokenGenerator 가 `.keyAgreement` proofPurpose 로 사용).
    static func generateKeyAgree(hWalletToken: String) throws {
        _ = try WalletAPI.shared.generateKeyPair(
            hWalletToken: hWalletToken,
            keyId: KeyIdName.keyAgree,
            algType: .secp256r1
        )
    }

    /// #bio — 생체 서명키. 생성 시점에 iOS 가 FaceID/TouchID prompt 를 띄우므로
    /// 취소·잠김 등의 실패를 BiometricError(BIO-E) 로 변환해 던진다.
    /// (서버/SDK 에러는 이 단계 밖에서 발생 — 호출 측 catch 가 따로 처리.)
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
