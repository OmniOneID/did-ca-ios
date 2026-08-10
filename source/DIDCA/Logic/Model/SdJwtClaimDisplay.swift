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

/// SD-JWT disclosure 값(`JSON`)을 화면 표시용으로 펼치는 공용 로직.
/// 상세화면(`CredentialStore`)과 VP 요청화면(`OID4VPPresenter`)이 같은 규칙을 써야
/// 두 화면의 중첩 클레임 표시가 어긋나지 않는다 — 이전엔 각자 복사돼 있었다.
// 순수 함수만 담는다(JSON in → String/배열 out; UI·상태 없음). 프로젝트 기본 격리가
// MainActor 라 명시 안 하면 MainActor 로 묶여, nonisolated 인 OID4VPPresenter 에서 호출 시
// actor-isolation 경고가 난다 — nonisolated 로 표시해 양쪽에서 자유롭게 호출한다.
nonisolated enum SdJwtClaimDisplay {

    /// SD-JWT 카드 제목. 목록·상세(`CredentialStore`)와 VP 제출 카드(`OID4VPPresenter`)가 같은
    /// 이름을 쓰도록 여기 한 곳에 모은다 — 무엇을 제목으로 삼을지 바뀌어도 호출부는 그대로다.
    ///
    /// ⚠️ 잠정: 지금은 `configurationId`(issuer metadata 의 설정 키)를 그대로 쓴다. 이 값은
    /// 크리덴셜의 정체가 아니라 발급 설정을 가리키고 SDK 에서 없어질 수 있어 표시용으로 적절하지
    /// 않다. 후보였던 페이로드의 `vct`(SD-JWT VC 타입)는 **다른 개발자와 협의가 끝난 뒤** 채택한다.
    /// 협의 결과가 나오면 이 함수 하나만 고치면 된다.
    static func title(of item: SdJwtCredentialItem) -> String {
        item.configurationId
    }

    /// 스칼라 JSON → 표시 문자열. 복합값(object/array)은 여기서 생략(빈 문자열),
    /// 하위 항목은 `childRows` 로 별도 펼친다(한 단계 중첩).
    static func scalarString(_ json: JSON) -> String {
        switch json {
        case .string(let value):    return value
        case .number(let digits):   return digits
        case .bool(let flag):       return flag ? "true" : "false"
        case .null:                 return ""
        case .object, .array:       return ""
        }
    }

    /// 복합값(object/array)의 하위 항목 목록. 스칼라·빈 값이면 빈 배열.
    /// - object → 키별 한 행. label 은 **발급된 키 원형** 그대로다(대소문자·구분자 변형 금지 —
    ///   키는 표시용 문구가 아니라 데이터이고, 검증자가 요구한 이름과 눈으로 대조할 수 있어야 한다).
    /// - array  → 라벨 없는 행(label=""). 인덱스는 발급자가 실은 값이 아니라 순서에 붙은 번호라
    ///   화면에 띄우면 없는 필드가 있는 것처럼 읽힌다. 행 순서가 이미 순서를 표현한다.
    ///   라벨이 빈 행은 값만 그린다(호출 측 `ClaimRow` / `VpClaimGroup`).
    /// `keySuffix` 는 부모 code 에 이어붙일 조각(`.field` / `[i]`) — 표시가 아니라 code 라
    /// 인덱스를 유지한다. code 를 쓰는 호출 측만 사용.
    static func childRows(_ json: JSON) -> [(label: String, value: String, keySuffix: String)] {
        switch json {
        case .object(let keyValues):
            return keyValues.map { (label: $0.key, value: scalarString($0.value), keySuffix: ".\($0.key)") }
        case .array(let elements):
            return elements.enumerated().map {
                (label: "", value: scalarString($0.element), keySuffix: "[\($0.offset)]")
            }
        default:
            return []
        }
    }
}
