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

/// Claim value — text or image (rendered keeping the original aspect ratio).
enum ClaimValue: Hashable {
    case text(String)
    case image(Data)
}

/// A single claim item (label + value). Also used as a child item of a collapsible group.
struct ClaimItem: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let value: ClaimValue
}

/// One item in the VC detail screen's claim list — a single row or a collapsible group.
/// Groups (based on VCSchema namespace) are for follow-up work; the current mapping produces only .row.
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
    /// VC claims to show in the "Certificate Details" section.
    let claims: [ClaimEntry]
    /// ZKP claims to show in the "Zero-Knowledge Proof" section (filled only when zkp == true).
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

    /// A copy with only the status changed. Used to overwrite with a status lookup result after all display data is built
    /// (SD-JWT is built from the expiry date first, then the Status List result is layered on).
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
