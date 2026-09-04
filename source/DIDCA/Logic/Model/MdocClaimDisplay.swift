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

/// mDoc(ISO/IEC 18013-5) 원소 값을 화면 표시용으로 옮기는 공용 로직.
/// 목록·상세(`CredentialStore`)와 VP 요청화면(`OID4VPPresenter`)이 같은 규칙을 쓰도록 한 곳에 모은다
/// — SD-JWT 쪽 `SdJwtClaimDisplay` 와 같은 자리다.
///
/// 원소 값은 JSON 이 아니라 CBOR 이라 문자열로만 다룰 수 없다. 세 갈래가 특히 중요하다.
/// - `.bytes` 는 바이트열이다. 이름이 이미지 화이트리스트에 들고 실제로 이미지로 열리면 그림으로,
///   아니면 `"(N bytes)"` 로 적는다(설계서 VC-B-01). 바이트를 문자열로 흉내 내지 않는다.
/// - `.fullDate` 는 **문자열 그대로** 둔다. 시각도 시간대도 없는 값이라 `Date` 로 바꾸면 표시할 때
///   하루가 밀 수 있다(SDK 문서 3절).
/// - `.dateTime` 만 실제 시점이라 포맷한다.
///
/// 상태 없는 순수 변환이라 `nonisolated` 다 — 프로토콜 계층이 메인 액터 밖에서 호출한다.
nonisolated enum MdocClaimDisplay {

    /// mDoc 카드 제목. SD-JWT 와 같은 규칙(`configurationId`)을 쓴다 — `SdJwtClaimDisplay.title` 참조.
    /// docType 은 제목이 아니라 발급기관 자리에 적는다(사람이 읽는 이름이 아니라 문서 종류라서).
    static func title(of item: MdocCredentialItem) -> String {
        item.configurationId
    }

    /// 원소 한 건의 표시값. 복합값(array/map)은 값 자리를 비우고 `childRows` 로 펼친다.
    ///
    /// 라벨은 `elementIdentifier` 원문 그대로다 — 네임스페이스를 앞에 붙이지 않는다.
    /// 발급자가 실어 보내는 원소 이름에 네임스페이스가 이미 들어 있어, 접두하면 두 번 나온다.
    static func claimValue(name: String, value: MdocElementValue) -> ClaimValue {
        switch value {
        case .bytes(let data):
            // 이미지 판정·`"(N bytes)"` 폴백은 ImageClaim 이 함께 쥔다(포맷별 판정 규칙과 같은 자리).
            return ImageClaim.claimValue(name: name, data: data)
        case .array, .map:
            return .text("")
        default:
            return .text(scalarString(value))
        }
    }

    /// 스칼라 원소 → 표시 문자열. 복합값·바이트열은 여기서 빈 문자열이다
    /// (바이트열은 `claimValue` 가 이미지나 크기 표기로 처리한다).
    static func scalarString(_ value: MdocElementValue) -> String {
        switch value {
        case .text(let text):       return text
        case .integer(let number):  return String(number)
        case .double(let number):   return String(number)
        case .bool(let flag):       return flag ? "true" : "false"
        case .fullDate(let date):   return date          // 발급자가 쓴 그대로 — 변환 금지.
        case .dateTime(let date):   return dateTimeFormatter.string(from: date)
        case .bytes, .array, .map, .null:
            return ""
        }
    }

    /// 복합값(array/map)의 하위 항목. 스칼라·빈 값이면 빈 배열.
    /// - map   → 키별 한 행. `Dictionary` 라 순회 순서가 실행마다 달라지므로 키로 정렬해 고정한다.
    /// - array → 라벨 없는 행(label=""). 인덱스는 발급자가 실은 값이 아니라 순서에 붙은 번호다.
    ///
    /// 하위가 또 복합값이면 값 자리가 빈다 — 화면이 한 단계만 그린다(SD-JWT 쪽과 같은 규칙).
    static func childRows(_ value: MdocElementValue) -> [(label: String, value: ClaimValue)] {
        switch value {
        case .map(let keyValues):
            return keyValues.sorted { $0.key < $1.key }
                .map { (label: $0.key, value: claimValue(name: $0.key, value: $0.value)) }
        case .array(let elements):
            return elements.map { (label: "", value: claimValue(name: "", value: $0)) }
        default:
            return []
        }
    }

    /// `.dateTime` 표기 — 날짜 부분은 목록의 ISSUED / VALID UNTIL 과 같은 모양이고, 실제 시점이라
    /// 시·분까지 붙인다. 시간대는 기기 로컬이다(발급자가 실은 값은 UTC 기준 시점 그 자체다).
    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd MMM yyyy HH:mm"
        return formatter
    }()
}
