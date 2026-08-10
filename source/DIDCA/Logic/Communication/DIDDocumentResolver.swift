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

// MARK: - 버전을 특정한 DID Document 조회 + 메모리 캐시
//
// 서명 검증에 쓰는 DID Document 는 **kid 에 실린 versionId 와 같은 버전**이어야 한다. fragment
// (`#assert`)가 같아도 버전이 다르면 같은 키라는 보장이 없어, 최신본으로 대체하면 정상 서명을
// 위조로 오판한다 (서버·클라 상호약속).
//
// 버전을 특정하면 그 문서는 불변이므로 캐시가 낡을 일이 없다 — TTL 도, 버전 비교도, 검증 실패 후
// 재조회도 필요 없다. 백그라운드 복귀 때 상태 캐시를 비우는 것과 달리 이 캐시는 유지하고,
// 지갑을 초기화할 때만 비운다.
//
// 최신본(versionId 미지정) 조회는 일부러 지원하지 않는다. 그건 가변이라 같은 규칙으로 캐시할 수
// 없고, 필요해지는 흐름(토큰 계열 certVc 검증)은 아직 최신본 요구 여부가 정해지지 않았다.
actor DIDDocumentResolver {

    static let shared = DIDDocumentResolver()
    private init() {}

    private struct Key: Hashable {
        let did: String
        let versionId: String
    }

    private var cache: [Key: DIDDocument] = [:]

    /// 지정한 버전의 DID Document. 캐시에 있으면 네트워크로 나가지 않는다.
    /// 조회 실패는 캐시에 남기지 않아 다음 호출이 다시 시도한다.
    func resolve(did: String, versionId: String) async throws -> DIDDocument {
        let key = Key(did: did, versionId: versionId)
        if let cached = cache[key] {
            return cached
        }
        let document = try await CommunicationClient.getDIDDocument(hostUrlString: URLs.API_URL,
                                                                   did: did,
                                                                   versionId: versionId)
        cache[key] = document
        return document
    }

    /// 지갑 초기화용. 문서 자체는 공개 정보지만 이전 지갑의 흔적을 남기지 않는다.
    func removeAll() {
        cache.removeAll()
    }
}
