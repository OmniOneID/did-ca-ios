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

// MARK: - Holder DID 문서 갱신 흐름 (UpdateUser)
//
// 온보딩 후 holder DID 문서가 이미 발행된 상태에서, 설정에서 BIO 를 켜고/끌 때
// 서버에 발행된 문서에 `#bio` verification method 를 추가/제거하는 흐름.
//
// 핵심: `updateHolderDIDDocument` 가 in-memory 문서에 #bio 를 add(키 있으면)/remove(없으면)
// 하고, 그 갱신된 문서를 `createSignedDIDDoc(passcode:)` 가 #pin 키로 서명해 서버에 제출한다.
// 서버는 기존 발행 문서 주인이 PIN 키로 서명했음을 검증해 갱신을 수락한다.
//
// 흐름 (campus-did-ca-ios UpdateUserProtocol 과 동등):
//   [1] updateHolderDIDDocument   메모리 문서에 #bio addVerificationMethod (없으면 remove)
//   [2] propose-update-diddoc     txId / authNonce 수령
//   [3] ECDH (.device)            sharedSecret 도출
//   [4] request-server-token      hServerToken
//   [5] getSignedDidAuth(PIN)     authNonce 를 #pin 키로 서명
//   [6] createSignedDIDDoc(PIN)   갱신 문서를 #pin 키로 서명
//   [7] request-update-diddoc     서명된 문서 제출
//   [8] confirm-update-diddoc     갱신 확정
//   [9] saveHolderDIDDocument     로컬 문서 저장
//
// 실패 시 [1] 에서 생성한 bio 키를 롤백(deleteKeyPair)해 로컬/서버 상태가 어긋나지 않게 한다.
nonisolated enum UpdateUserProtocol {

    /// bio 키 생성 + DID 문서에 #bio 반영. 설정 > Add Biometrics 진입점.
    /// generateBio 는 생체 prompt 실패를 BiometricError(BIO-E) 로 던진다 — 호출 측이 분기.
    static func addBioKey(passcode: String) async throws {
        let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .UPDATE_DID)
        try WalletKeys.generateBio(hWalletToken: hWalletToken)
        // 키 생성 후 문서 갱신용 토큰을 새로 받는다 (campusID 와 동일 — 발급 토큰은 단계마다 신규).
        let updateToken = try await TokenGenerator.requestWalletToken(purpose: .UPDATE_DID)
        try await update(hWalletToken: updateToken, passcode: passcode)
    }

    /// bio 키 삭제 + DID 문서에서 #bio 제거. (설정에서 BIO 끄기용 — UI 연결은 추후.)
    static func deleteBioKey(passcode: String) async throws {
        let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .UPDATE_DID)
        try WalletAPI.shared.deleteKeyPair(hWalletToken: hWalletToken, keyId: KeyIdName.bio)
        try await update(hWalletToken: hWalletToken, passcode: passcode)
    }

    // MARK: - 공통 갱신 흐름
    //
    // updateHolderDIDDocument 내부가 isKeySaved(bio) 로 add/remove 를 자동 분기하므로
    // add/delete 가 같은 흐름을 공유한다.
    private static func update(hWalletToken: String, passcode: String) async throws {
        do {
            let didDoc = try WalletAPI.shared.getDidDocument(type: .HolderDidDocumnet)

            let propose = try await TASConnection.proposeUpdateDidDoc(did: didDoc.id)

            let sharedSecret = try await TokenGenerator.getSharedSecret(type: .device, txId: propose.txId)
            let hServerToken = try await TokenGenerator.requestServerToken(
                purpose: .UPDATE_DID,
                txId: propose.txId,
                sharedSecret: sharedSecret
            )

            let didAuth = try WalletAPI.shared.getSignedDidAuth(
                authNonce: propose.authNonce,
                passcode: passcode
            )
            
            let _ = try WalletAPI.shared.updateHolderDIDDocument(hWalletToken: hWalletToken)
            
            let signedDIDDoc = try WalletAPI.shared.createSignedDIDDoc(passcode: passcode)

            
            let response = try await WalletAPI.shared.requestUpdateUser(
                tasURL: URLs.TAS_URL + "/tas/api/v1/request-update-diddoc",
                txId: propose.txId,
                hWalletToken: hWalletToken,
                serverToken: hServerToken,
                didAuth: didAuth,
                signedDIDDoc: signedDIDDoc
            )

            try await TASConnection.confirmUpdateDidDoc(txId: response.txId, serverToken: hServerToken)
            try WalletAPI.shared.saveHolderDIDDocument()
        } catch {
            // 갱신 실패 시 방금 만든 bio 키를 되돌려 로컬(키)/서버(문서) 불일치를 막는다.
            // (campus-did-ca-ios 동일 — add 경로 기준. delete 경로 롤백은 추후 키 복원 API 필요.)
            if Biometrics.hasBioKey {
                try? WalletAPI.shared.deleteKeyPair(hWalletToken: hWalletToken, keyId: KeyIdName.bio)
            }
            throw error
        }
    }
}
