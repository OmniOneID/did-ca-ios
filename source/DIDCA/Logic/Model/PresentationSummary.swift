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

// MARK: - VP 요청 화면 표시 데이터
//
// 프로토콜 계층이 만들고 화면이 소비하는 공용 표시 모델. 특정 프로토콜에 종속되지 않는다 —
// 일반 VP(`VerifyVcProtocol`)와 OID4VP(`OID4VPPresenter`)가 같은 `VpPresentationSummary` 를
// 만들어 같은 화면(`VPRequestView`)에 넘긴다.

struct VpPresentationClaim {
    /// 제출에 나가는 claim code. **SDK 가 준 값 그대로**이며 앱이 만들거나 쪼개지 않는다
    /// (SD-JWT·mDoc 은 `consentItems`, W3C 는 VC claim code).
    ///
    /// `nil` 이면 **제출 단위가 아닌 행**이다 — 따로 뺄 수단이 없어 상위·원소와 함께 나간다
    /// (SD-JWT rideAlong, mDoc 복합값의 원소). 체크박스를 그리지 않는다.
    let code: String?
    let label: String
    /// 텍스트 또는 이미지(portrait 등). 이미지면 값 텍스트를 대신한다 — 판정은 `ImageClaim` 참조.
    let value: ClaimValue
    /// REQUIRED 섹션 소속 — 사용자가 뺄 수 없고 항상 제출된다. **체크박스를 그리지 않는다**
    /// (회색 비활성 체크박스를 쓰지 않는다 — PRES-B-02).
    /// `false` 면 OPTIONAL 섹션이며 **해제 상태로 시작한다**(opt-in).
    ///
    /// 필수는 상위에서만 내려오고 서브트리 전체로 전파된다 — 상위가 REQUIRED 면 하위도 REQUIRED 다.
    let required: Bool
    /// 하위 항목. 비어 있으면 단일 행, 있으면 접이식 그룹으로 표시한다(한 단계만 그린다).
    ///
    /// **하위는 개별 체크박스를 갖지 않는다** — 그룹은 상위 체크박스 하나로 통째 토글한다(PRES-B-03).
    /// 하위의 `code` 는 제출 집합을 만들 때만 쓴다(상위를 켜면 하위 code 도 함께 나간다).
    /// W3C VC 는 항상 비어 있다.
    var children: [VpPresentationClaim] = []
}

/// VP 요청 화면에 표시할 제출 대상 문서 (크리덴셜 1건).
///
/// 화면과 제출이 같은 근거를 쓰도록, 프로토콜 계층이 한 번만 산출해 여기에 담는다.
/// 카드 하나는 네 집합으로 기술된다 — 노출(`claims`), 필수(`claims[].required`),
/// 체크(화면이 보유), 제출(`requiredCodes ∪ 체크`).
struct VpPresentationDocument {
    let credentialId: String
    let title: String
    /// 노출 집합. REQUIRED 는 항상 제출되고, OPTIONAL 은 해제 상태로 시작한다.
    let claims: [VpPresentationClaim]
    /// 토글과 무관하게 항상 제출되는 code — 노출 집합의 REQUIRED 행(과 그 하위)과 같은 집합이다.
    ///
    /// **필수는 화면에 숨기지 않는다**(PRES-B-06) — OpenDID 프로파일의 `requiredClaims` 가
    /// `displayClaims` 밖에 있어도 노출 집합에 합쳐 그린다. 그래도 이 집합을 따로 들고 다니는 것은
    /// 제출 산출을 노출 트리 순회에 의존시키지 않기 위해서다(하위 code 까지 한 곳에 모인다).
    let requiredCodes: Set<String>
    /// OID4VC 발급분(SD-JWT·mDoc) 전용 — 이 크리덴셜이 **발급 시 바인딩된** 서명키 id
    /// (`KeyIdName.pin` / `.bio`).
    /// 제출 인증수단은 사용자가 고르는 게 아니라 이 값이 정한다: SDK 는 크리덴셜마다
    /// `walletCore.sign(keyId: item.kid, …)` 로 서명하므로 바인딩을 바꿀 수 없다.
    /// W3C 카드는 nil (그쪽은 passcode 유무로 서명키가 갈려 사용자가 고를 수 있다).
    let bindingKeyId: String?
}

/// 검증자명 + 제출 **후보** 목록 — VPRequestView 표시용.
///
/// 후보가 2건 이상이면 화면이 라디오 옵션 카드로 갈리고 **그중 1건만 제출된다**(PRES-B-05).
/// 후보는 ACTIVE 인 것만 담긴다(PRES-B-06) — 0건이면 프로토콜 계층이 제출 불가로 중단한다.
struct VpPresentationSummary {
    let verifierName: String
    let documents: [VpPresentationDocument]
}

// MARK: - ZKP VP 요청 화면 표시 데이터 (`VPRequestZkpView` 용)

/// 하나의 sub-referent 표시 — raw 값과 그 값이 나온 schema 이름을 함께 묶어,
/// 같은 raw 값을 가진 sub-referent 들이 picker 에서 다른 row 로 구분되도록 한다.
/// did-ca-ios `AttrSelectionViewController` 의 cell (nameLabel = schema.name, valueLabel = raw) 대응.
struct ZkpAvailableValue {
    let raw: String
    let schemaName: String
}

struct ZkpPresentationClaim {
    /// AvailableReferent.attrReferent[].key — coordinator 선택/입력 dictionary 의 키.
    let key: String
    let label: String
    /// 사용자가 picker 로 고를 수 있는 후보 — AvailableReferent.attrReferent[].referent[] 와 1:1.
    /// index 가 그대로 UserReferent(attrReferent:selectedIndex:) 의 selectedIndex 로 사용됨.
    /// did-ca-ios 와 동일하게 predicate 도 후보 리스트를 제공해 사용자가 선택. self-attribute 는 비어 있음.
    let availableValues: [ZkpAvailableValue]
}

/// VPRequestZkpView 표시 모델 — did-ca-ios `ZKPSubmissionViewController` 와 동일하게
/// 단일 화면에 Attributes / Predicates / Self-Attributes 세 그룹이 평탄하게 나열된다
/// (document 단위 grouping 없음).
struct ZkpPresentationSummary {
    let verifierName: String
    let title: String
    let attributes: [ZkpPresentationClaim]
    let predicates: [ZkpPresentationClaim]
    let selfAttributes: [ZkpPresentationClaim]
}
