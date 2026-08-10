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
    let code: String
    let label: String
    let value: String
    /// 체크 해제 불가 — 화면에 뜬 필수 항목. 진입 시부터 체크된 채 disabled 로 그려진다.
    let locked: Bool
    /// 하위 항목(SD-JWT 복합값 disclosure 의 object/array 필드). 비어 있으면 단일 행,
    /// 있으면 접이식 그룹으로 표시한다. W3C VC 는 항상 비어 있다.
    var children: [VpPresentationClaim] = []
}

/// VP 요청 화면에 표시할 제출 대상 문서 (크리덴셜 1건).
///
/// 화면과 제출이 같은 근거를 쓰도록, 프로토콜 계층이 한 번만 산출해 여기에 담는다.
/// 카드 하나는 네 집합으로 기술된다 — 노출(`claims`), 잠금(`claims[].locked`),
/// 체크(화면이 보유), 제출(`requiredCodes ∪ 체크`).
struct VpPresentationDocument {
    let credentialId: String
    let title: String
    /// 노출 집합. 진입 시 전부 체크된 상태로 시작한다.
    let claims: [VpPresentationClaim]
    /// 토글과 무관하게 항상 제출되는 code.
    ///
    /// OpenDID 제출 프로파일은 `requiredClaims` 가 `displayClaims` 밖에 있을 수 있어(화면에 숨긴 채 제출)
    /// 노출 집합만으로는 복원할 수 없다 — 그래서 별도로 들고 다닌다. DCQL 경로는 노출이 항상 크리덴셜
    /// 전체라 이 집합이 노출 집합의 부분집합이고, 잠금은 늘 체크 상태이므로 제출 산출에 영향을 주지 않는다.
    let requiredCodes: Set<String>
    /// SD-JWT 전용 — 이 크리덴셜이 **발급 시 바인딩된** 서명키 id (`KeyIdName.pin` / `.bio`).
    /// 제출 인증수단은 사용자가 고르는 게 아니라 이 값이 정한다: SDK 는 크리덴셜마다
    /// `walletCore.sign(keyId: item.kid, …)` 로 서명하므로 바인딩을 바꿀 수 없다.
    /// W3C 카드는 nil (그쪽은 passcode 유무로 서명키가 갈려 사용자가 고를 수 있다).
    let bindingKeyId: String?
}

/// 검증자명 + 제출 대상 문서 목록 — VPRequestView 표시용.
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
