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

    // MARK: - 동의 항목 → 화면 행
    //
    // 상세화면(`CredentialStore`)과 VP 제출 동의화면(`OID4VPPresenter`)이 **같은 근거·같은 구성**으로
    // 그리도록 여기 한 곳에서 만든다. 근거는 SDK `consentItems` 다 — claim code 를 앱이 만들지
    // 않는다는 원칙(SDK 문서 4절)이 두 화면에 함께 적용된다.
    //
    // 순서는 SDK 가 준 순서를 그대로 쓴다 — 발급자가 크리덴셜에 실은 disclosure 순서다
    // (SDK `31f9fbb`. 그 전에는 code 오름차순이었다). mDoc 이 발급자 서명 순서를 따르는 것과 같은
    // 원칙이며, 앱이 다시 정렬하지 않는다.

    /// 화면 한 행 — 상위 claim 하나와 그 아래 붙는 것들.
    struct ConsentRow {
        let item: SdJwtConsentItem
        /// 자기 code 를 갖는 하위 claim. 따로 공개할 수 있어 제출 화면에서는 각자 체크박스가 붙는다.
        let nested: [SdJwtConsentItem]
        /// 상위와 함께 공개돼 따로 뺄 수 없는 값 안의 멤버. 표시 전용이다.
        let rideAlong: [(label: String, value: String)]
    }

    /// `consentItems` → 화면 행 목록. 화면에 내놓지 않는 두 갈래를 먼저 걷어낸다.
    ///
    /// - `isAmbiguous`: 한 code 가 claim 두 개 이상을 가리킨다. 어느 쪽에 동의했는지 확정할 수 없어
    ///   SDK 가 제출을 실패시키므로, 지킬 수 없는 동의를 받지 않는다.
    /// - `isSelectivelyDisclosable == false`: 발급자가 평문으로 실어 둔 claim 이라 감출 수단이 없다.
    ///   현행 화면과 같게 목록에서 뺀다(결정 2026-08-12). 제출 화면에서는 verifier 가 요구한 평문
    ///   code 가 `requiredCodes` 로 따로 실려 제출 집합에는 그대로 들어간다.
    ///
    /// 중첩은 code 간 접두 관계로 **표시에서만** 판정한다 — code 자체는 쪼개지도 만들지도 않는다.
    /// 발급자가 `address.street_address` 를 한 조각 이름으로 실으면 화면에서 `address` 밑으로 잘못
    /// 접히지만, code 는 그대로라 제출에는 영향이 없다.
    static func consentRows(_ items: [SdJwtConsentItem]) -> [ConsentRow] {
        let rows = items.filter { !$0.isAmbiguous && $0.isSelectivelyDisclosable }
        let codes = Set(rows.map(\.code))

        var childrenByRoot: [String: [SdJwtConsentItem]] = [:]
        var roots: [SdJwtConsentItem] = []
        for item in rows {
            if let root = rootCode(of: item.code, in: codes) {
                childrenByRoot[root, default: []].append(item)
            } else {
                roots.append(item)
            }
        }

        return roots.map { root in
            // 값 안의 멤버 중 자기 code 를 갖는 것(= nested)은 뺀다 — 남기면 같은 값이 체크박스 있는
            // 행과 없는 행으로 두 번 나온다.
            let rideAlong = childRows(root.value)
                .filter { !codes.contains(root.code + $0.keySuffix) }
                .map { (label: $0.label, value: $0.value) }
            return ConsentRow(item: root,
                              nested: childrenByRoot[root.code] ?? [],
                              rideAlong: rideAlong)
        }
    }

    /// consent 항목의 표시값 — 이미지 판정은 claim 이름 화이트리스트 기준(`ImageClaim` 참조).
    /// 이름은 code 전체 경로가 아니라 마지막 조각을 쓴다 — 그게 발급자가 붙인 이름이다.
    static func value(of item: SdJwtConsentItem) -> ClaimValue {
        ImageClaim.claimValue(name: item.claimName, text: scalarString(item.value))
    }

    /// `code` 를 품는 **가장 바깥** claim 의 code — 없으면 nil(자기가 최상위다).
    ///
    /// 화면이 한 단계만 그리므로 가장 가까운 상위가 아니라 최상위에 붙인다. 손자를 부모에 붙이면
    /// 그 부모가 다시 누군가의 하위로 들어가면서 행이 통째로 화면에서 사라진다.
    private static func rootCode(of code: String, in codes: Set<String>) -> String? {
        codes
            .filter { $0.count < code.count && code.hasPrefix($0) && isBoundary(code, after: $0) }
            .min { $0.count < $1.count }
    }

    /// 접두 뒤가 경계(`.` 또는 `[`)인지 — `addressed` 가 `address` 의 하위로 잡히는 것을 막는다.
    private static func isBoundary(_ code: String, after prefix: String) -> Bool {
        let next = code[code.index(code.startIndex, offsetBy: prefix.count)]
        return next == "." || next == "["
    }

    // MARK: - 값 변환

    /// 스칼라 `AnyJSON` → 표시 문자열. `consentItems`(SDK)가 값을 이 타입으로 준다.
    ///
    /// 숫자는 JSON 규격상 `Double` 하나로 오므로 소수부가 없으면 정수로 되돌려 적는다 —
    /// 그대로 쓰면 발급자가 실은 `1990` 이 화면에 `1990.0` 으로 나온다.
    static func scalarString(_ json: AnyJSON) -> String {
        switch json {
        case .string(let value):    return value
        case .number(let value):    return numberString(value)
        case .bool(let flag):       return flag ? "true" : "false"
        case .null:                 return ""
        case .object, .array:       return ""
        }
    }

    private static func numberString(_ value: Double) -> String {
        guard value.rounded() == value, abs(value) < 1e15 else { return String(value) }
        return String(Int64(value))
    }

    /// 복합값(object/array)의 하위 항목 목록. 스칼라·빈 값이면 빈 배열.
    /// - object → 키별 한 행. label 은 **발급된 키 원형** 그대로다(대소문자·구분자 변형 금지 —
    ///   키는 표시용 문구가 아니라 데이터이고, 검증자가 요구한 이름과 눈으로 대조할 수 있어야 한다).
    ///   `AnyJSON.object` 는 `Dictionary` 라 순회 순서가 실행마다 달라지므로 키로 정렬해 고정한다.
    /// - array  → 라벨 없는 행(label=""). 인덱스는 발급자가 실은 값이 아니라 순서에 붙은 번호라
    ///   화면에 띄우면 없는 필드가 있는 것처럼 읽힌다. 행 순서가 이미 순서를 표현한다.
    ///   라벨이 빈 행은 값만 그린다(호출 측 `ClaimRow` / `VpClaimGroup`).
    ///
    /// `keySuffix` 는 부모 code 에 이어붙였을 때 이 멤버를 가리키게 되는 조각(`.field` / `[i]`)이다.
    /// **제출용 code 를 만드는 데 쓰면 안 된다** — 제출에 나가는 code 는 SDK `consentItems` 가 준
    /// 값뿐이다. 여기서의 쓰임은 "이 멤버가 따로 공개할 수 있는 claim 인가"를 그 목록과 대조하는
    /// 것뿐이며(대조 후 쓰는 값도 SDK 가 준 code), 그래서 인덱스를 유지한다.
    static func childRows(_ json: AnyJSON) -> [(label: String, value: String, keySuffix: String)] {
        switch json {
        case .object(let keyValues):
            return keyValues.sorted { $0.key < $1.key }
                .map { (label: $0.key, value: scalarString($0.value), keySuffix: ".\($0.key)") }
        case .array(let elements):
            return elements.enumerated().map {
                (label: "", value: scalarString($0.element), keySuffix: "[\($0.offset)]")
            }
        default:
            return []
        }
    }
}
