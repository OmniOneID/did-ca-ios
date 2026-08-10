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

import SwiftUI

enum CredentialFormat: String {
    case sdJwt = "SD-JWT"
    case mDoc = "mDoc"
    case vc = "VC"
    case zkp = "ZKP"
}

enum CredentialStatus: String {
    case active = "Active"
    case inactive = "Inactive"
    case expired = "Expired"
}

/// 클레임 값 — 텍스트 또는 이미지(원본 비율 유지 렌더링).
enum ClaimValue: Hashable {
    case text(String)
    case image(Data)
}

/// 단일 클레임 항목 (라벨 + 값). 접이식 그룹의 하위 항목으로도 쓰인다.
struct ClaimItem: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let value: ClaimValue
}

/// VC 상세화면 클레임 목록의 한 항목 — 단일 행 또는 접이식 그룹.
/// 그룹(VCSchema namespace 기반)은 후속 작업용이며, 현재 매핑은 .row 만 생성한다.
struct ClaimEntry: Identifiable, Hashable {
    enum Kind: Hashable {
        case row(label: String, value: ClaimValue)
        case group(title: String, items: [ClaimItem])
    }
    let id = UUID()
    let kind: Kind
}

struct Credential: Identifiable, Hashable {
    let id: String
    let name: String
    let badge: CredentialFormat
    let issuer: String
    let issued: String?
    let valid: String?
    let status: CredentialStatus
    let zkp: Bool
    let icon: ImageResource
    /// "Certificate Details" 섹션에 표시할 VC 클레임.
    let claims: [ClaimEntry]
    /// "Zero-Knowledge Proof" 섹션에 표시할 ZKP 클레임 (zkp == true 일 때만 채워짐).
    let zkpClaims: [ClaimItem]

    init(
        id: String,
        name: String,
        badge: CredentialFormat,
        issuer: String,
        issued: String? = nil,
        valid: String? = nil,
        status: CredentialStatus,
        zkp: Bool = false,
        icon: ImageResource = .icId,
        claims: [ClaimEntry] = [],
        zkpClaims: [ClaimItem] = []
    ) {
        self.id = id
        self.name = name
        self.badge = badge
        self.issuer = issuer
        self.issued = issued
        self.valid = valid
        self.status = status
        self.zkp = zkp
        self.icon = icon
        self.claims = claims
        self.zkpClaims = zkpClaims
    }

    /// 상태만 바꾼 사본. 표시 데이터를 다 만든 뒤 상태 조회 결과로 덮어쓸 때 쓴다
    /// (SD-JWT 는 만료일로 먼저 만들고 Status List 결과를 얹는다).
    func with(status: CredentialStatus) -> Credential {
        Credential(
            id: id,
            name: name,
            badge: badge,
            issuer: issuer,
            issued: issued,
            valid: valid,
            status: status,
            zkp: zkp,
            icon: icon,
            claims: claims,
            zkpClaims: zkpClaims
        )
    }
}

enum SampleCredentials {
    static let ehic1 = Credential(
        id: "ehic1",
        name: "DC4EU European Health Insurance Card",
        badge: .sdJwt,
        issuer: "Digital Credentials Issuer",
        valid: "29 May 2026",
        status: .inactive,
        icon: .icId
    )
    static let ehic2 = Credential(
        id: "ehic2",
        name: "DC4EU European Health Insurance Card",
        badge: .sdJwt,
        issuer: "Digital Credentials Issuer",
        valid: "29 May 2026",
        status: .active,
        icon: .icShield
    )
    static let learning = Credential(
        id: "learn",
        name: "Learning Credential",
        badge: .sdJwt,
        issuer: "EU Learning Authority",
        valid: "15 Aug 2027",
        status: .active,
        icon: .icBuilding
    )
    static let mdl = Credential(
        id: "mdl",
        name: "Mobile Driving License",
        badge: .mDoc,
        issuer: "Department of Motor Vehicles",
        issued: "12 Mar 2024",
        valid: "12 Mar 2028",
        status: .active,
        icon: .icId
    )
    static let natId = Credential(
        id: "natid",
        name: "National ID Card",
        badge: .vc,
        issuer: "Government Identity Service",
        issued: "20 Dec 2024",
        valid: "20 Dec 2029",
        status: .active,
        zkp: true,
        icon: .icId
    )
    static let driverLicense = Credential(
        id: "dl",
        name: "Driver License",
        badge: .vc,
        issuer: "Department of Motor Vehicles",
        valid: "12 Mar 2028",
        status: .expired,
        icon: .icId
    )
    static let resident = Credential(
        id: "resident",
        name: "Resident Registration Card",
        badge: .vc,
        issuer: "Ministry of the Interior",
        valid: "05 Nov 2030",
        status: .active,
        zkp: true,
        icon: .icShield
    )

    static let all: [Credential] = [ehic1, ehic2, learning, mdl, natId, driverLicense, resident]
}
