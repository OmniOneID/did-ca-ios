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

enum JWSSignerError: Error {
    /// `kid` 가 `did:...?versionId=N#fragment` 형태가 아님 — 검증할 문서 버전을 특정할 수 없다.
    case invalidKeyIdentifier
    /// DID Document 에 그 fragment 의 verificationMethod 가 없거나 공개키를 읽을 수 없음.
    case unknownSigningKey
    /// 서명이 그 키의 것이 아님.
    case signatureVerificationFailed
}

/// JWS 를 **서명자의 DID Document 에 실린 공개키**로 검증한다.
///
/// SDK `JWS.verify()`(무인자)는 헤더에 실린 `jwk` 로 검증한다. 그건 "서명 후 변조되지 않았다"만
/// 보증하고 **누가 서명했는지는 보증하지 않는다** — 키를 요청자가 스스로 넣어 보내기 때문이다.
/// 헤더에 `kid` 가 함께 있어도 마찬가지다: 아무도 그 `jwk` 가 `kid` 가 가리키는 주체의 키인지
/// 대조하지 않으므로, `kid` 문자열만 베끼고 자기 키로 서명하면 그대로 통과한다.
///
/// 그래서 여기서는 `jwk` 를 **무시하고** `kid` 가 가리키는 DID Document 를 받아 그 안의 공개키로
/// 검증한다. 신뢰의 근거가 요청 바깥(DID 레지스트리)에 있어야 신원이 성립한다.
/// 서명 검증 자체는 SDK `JWS.verify(publicKey:)` 가 한다 — SDK 가 키 해석과 신뢰 판단을 호출자
/// 몫으로 남겨 둔 진입점이다.
nonisolated enum JWSSignerVerifier {

    /// `kid` → DID Document → 공개키로 서명 검증. 통과하지 못하면 던진다.
    ///
    /// - parameter jws: 검증할 JWS.
    /// - parameter kid: 헤더의 `kid`. `did:omn:issuer?versionId=1#assert` 형태여야 한다.
    static func verify(jws: JWS, kid: String) async throws {
        guard let identifier = parseKeyIdentifier(kid) else {
            throw JWSSignerError.invalidKeyIdentifier
        }

        // 반드시 kid 가 지정한 버전으로 받는다 — 최신본은 같은 fragment 라도 다른 키일 수 있다.
        // 버전이 특정된 문서는 불변이라 resolver 가 무기한 캐시한다.
        let didDocument = try await DIDDocumentResolver.shared.resolve(did: identifier.did,
                                                                      versionId: identifier.versionId)
        guard let method = didDocument.verificationMethod.first(where: { $0.id == identifier.keyId }),
              let publicKey = try? MultibaseUtils.decode(encoded: method.publicKeyMultibase)
        else {
            throw JWSSignerError.unknownSigningKey
        }

        guard (try? jws.verify(publicKey: publicKey)) == true else {
            throw JWSSignerError.signatureVerificationFailed
        }
    }

    /// 서명 키를 가리키는 식별자 — `did:omn:issuer?versionId=1#assert` 의 세 조각.
    /// DID Document 의 verificationMethod.id 는 fragment 만(`assert`) 담고 있다.
    private struct KeyIdentifier {
        let did: String
        let versionId: String
        let keyId: String
    }

    /// kid 파싱. **versionId 는 필수** — 없으면 검증할 문서 버전을 특정할 수 없어 nil 을 돌려주고,
    /// 호출측이 최신본으로 물러나지 않고 실패시킨다. SDK `DIDUtility.parseDIDKeyIdentifier` 와 같은
    /// 규약이지만 그쪽이 internal 이라 여기에 같은 해석을 둔다.
    private static func parseKeyIdentifier(_ kid: String) -> KeyIdentifier? {
        let fragmentParts = kid.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard fragmentParts.count == 2 else { return nil }

        let versionParts = fragmentParts[0].components(separatedBy: "?versionId=")
        guard versionParts.count == 2 else { return nil }

        let identifier = KeyIdentifier(did: versionParts[0],
                                       versionId: versionParts[1],
                                       keyId: String(fragmentParts[1]))
        guard !identifier.did.isEmpty, !identifier.versionId.isEmpty, !identifier.keyId.isEmpty else {
            return nil
        }
        return identifier
    }
}
