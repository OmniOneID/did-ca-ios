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

extension ZKPCredentialSchema {

    /// ZKP 클레임 키(`namespace.id.label`) → caption(사람이 읽는 라벨) 매핑.
    /// 상세화면(`CredentialStore`)과 제출화면(`VerifyZKProofProtocol`) 양쪽이 공유한다.
    /// did-ca-ios `VCDetailViewController` / `makeReferentNameMap` 과 동일 패턴.
    var captionMap: [String: String] {
        var dict: [String: String] = [:]
        for attr in attrTypes {
            for item in attr.items {
                dict["\(attr.namespace.id).\(item.label)"] = item.caption
            }
        }
        return dict
    }
}

extension Sequence where Element == ZKPCredentialSchema {

    /// 여러 schema 의 captionMap 을 하나로 평탄화. 키 충돌 시 뒤 값 우선.
    var mergedCaptionMap: [String: String] {
        reduce(into: [String: String]()) { dict, schema in
            dict.merge(schema.captionMap) { _, new in new }
        }
    }
}
