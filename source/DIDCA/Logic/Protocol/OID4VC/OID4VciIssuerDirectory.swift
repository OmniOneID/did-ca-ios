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

enum OID4VciDirectoryError: Error {
    /// holder DID 또는 userName 이 없어 시작 URL 을 만들 수 없음 (미바인딩 지갑).
    case missingUserBinding
    /// user initiation URI 가 URL 로 파싱되지 않거나 host 가 없음.
    case invalidStartURL
    /// user initiation URI 의 scheme 이 http/https 가 아님.
    case unsupportedStartScheme
    /// 선택한 credential configuration id 가 issuer metadata 에 없음.
    case unknownConfiguration
    /// 완료 redirect 가 규격에 맞지 않음 — credential_offer_uri 누락 / credential_offer 와 동시 존재 /
    /// 디코딩 결과가 절대 http·https URI 가 아님.
    case invalidCompletionURI
    /// 이미 소비한 Credential Offer 를 다시 처리하려 함 (중복 redirect).
    case offerAlreadyConsumed
}

// MARK: - OID4VCI 목록사업자 디렉터리 + user-initiation WebView 연동
//
// 연동 가이드("OID4VCI WebView 사용자 클레임 입력 연동") §3·§5·§7 에 해당한다. WebView 는
// Issuer 의 클레임 입력 화면을 띄우고 완료 redirect 를 받아오는 역할만 하며, Token/Nonce/Proof/
// Credential Request 는 일절 수행하지 않는다 — 완료 후에는 QR·딥링크 발급과 **같은** 경로
// (`IssueOID4VcProtocol`)로 합류한다.
//
//   [1] issuers()                목록사업자 공개 API → 활성 Issuer 목록
//   [2] (앱 UI) Issuer 선택 → metadata 조회 → credential configuration 선택
//   [3] startURL(...)            did·userName·configuration id 를 실은 WebView 시작 URL
//   [4] (WebView) 클레임 입력 → OK → openid-credential-offer:// redirect
//   [5] credentialOfferURI(from:) redirect 에서 credential_offer_uri 추출·검증
//   [6] 기존 발급 경로(handleOID4VCI)에 그대로 전달
//
// JS 브리지는 쓰지 않는다. 입력한 클레임은 Issuer DB 에 저장되고 앱은 오퍼 URI 만 받는다.
nonisolated enum OID4VciIssuerDirectory {

    /// 완료 redirect 의 custom scheme. 이 스킴만 완료 응답으로 처리하고, 외부 앱 실행으로 넘기지 않는다.
    static let completionScheme = "openid-credential-offer"

    /// 목록사업자의 OID4VCI 지원 Issuer 목록. 인증 정보 없이 호출하며 request body·query 는 없다.
    /// 서버는 ACTIVE 로 승인된 Issuer 만 등록일 오름차순으로 반환한다. 지원 Issuer 가 없으면 빈 배열.
    static func issuers() async throws -> [OID4VCIIssuerItem] {
        let list: OID4VCIIssuerList = try await CommunicationClient.sendRequest(
            urlString: URLs.TAS_URL + "/list/api/v1/oid4vci/issuers",
            httpMethod: .GET
        )
        return list.items
    }

    /// WebView 시작 URL — `{userInitiationUri}?did=…&userName=…&credential_configuration_id=…`.
    ///
    /// 쿼리는 `URLComponents` 가 항목별로 인코딩한다(URL 문자열 전체를 한 번에 인코딩하면 안 된다).
    /// 싣는 값은 기존 OpenDID 발급 웹 폼(`IssueVcProtocol.webFormURL`)과 같은 did/userName 두 개다 —
    /// 가이드 §5 의 `userId` 대신 `userName` 을 쓰기로 서버와 협의됐고, DID 도 함께 넘긴다.
    /// Claim·토큰·Pre-Authorized Code 등 그 밖의 값은 쿼리로 전달하지 않는다.
    ///
    /// - parameter did: holder DID (`WalletState.holderDID`). 미바인딩이면 nil 로 넘어와 거부된다.
    /// - parameter userName: 사용자 식별 값 (`WalletState.userName`). 위와 같다.
    /// - parameter credentialType: configuration 에 identifier 가 여러 개일 때만 전달. 현재 서버
    ///   metadata 에는 `credential_identifiers` 가 없어 nil 로 호출된다.
    static func startURL(userInitiationUri: String,
                         configurationId: String,
                         did: String?,
                         userName: String?,
                         credentialType: String? = nil,
                         metadata: IssuerMetadataResponse) throws -> URL {
        guard metadata.credentialConfigurationsSupported[configurationId] != nil else {
            throw OID4VciDirectoryError.unknownConfiguration
        }
        guard var components = URLComponents(string: userInitiationUri) else {
            throw OID4VciDirectoryError.invalidStartURL
        }
        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw OID4VciDirectoryError.unsupportedStartScheme
        }
        guard let host = components.host, !host.isEmpty else {
            throw OID4VciDirectoryError.invalidStartURL
        }
        guard let did, !did.isEmpty, let userName, !userName.isEmpty else {
            throw OID4VciDirectoryError.missingUserBinding
        }

        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "did", value: did))
        items.append(URLQueryItem(name: "userName", value: userName))
        items.append(URLQueryItem(name: "credential_configuration_id", value: configurationId))
        if let credentialType, !credentialType.isEmpty {
            items.append(URLQueryItem(name: "credential_type", value: credentialType))
        }
        components.queryItems = items

        guard let url = components.url else {
            throw OID4VciDirectoryError.invalidStartURL
        }
        return url
    }

    /// 완료 redirect(`openid-credential-offer://?credential_offer_uri=…`)에서 오퍼 URI 를 꺼낸다.
    ///
    /// 가이드 §7 의 거부 조건을 그대로 구현한다 — `credential_offer` 와 `credential_offer_uri` 가
    /// 동시에 있으면 거부하고, 디코딩은 `URLComponents` 가 **정확히 한 번** 수행하며(직접 추가
    /// 디코딩 금지), 결과가 절대 http·https URI 가 아니면 거부한다.
    static func credentialOfferURI(from url: URL) throws -> String {
        guard url.scheme?.lowercased() == completionScheme,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else {
            throw OID4VciDirectoryError.invalidCompletionURI
        }

        // by-value 오퍼(credential_offer)는 이 연동에서 쓰지 않는다. 둘 다 오면 어느 쪽이 정본인지
        // 알 수 없으므로 거부한다.
        guard items.first(where: { $0.name == "credential_offer" })?.value == nil,
              let reference = items.first(where: { $0.name == "credential_offer_uri" })?.value,
              !reference.isEmpty
        else {
            throw OID4VciDirectoryError.invalidCompletionURI
        }

        guard let offerURL = URL(string: reference),
              let scheme = offerURL.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = offerURL.host, !host.isEmpty
        else {
            throw OID4VciDirectoryError.invalidCompletionURI
        }
        return reference
    }

    /// Issuer 식별자 동일성 판정 — scheme·host·port·path 를 정규화해 비교한다.
    /// 단순 문자열 prefix 비교를 쓰지 않는다(가이드 §8). 기본 포트(80/443)는 생략과 같게 본다.
    ///
    /// 양쪽 중 하나라도 http·https URL 이 아니면(예: DID) 정규화할 축이 없으므로 문자열 일치로 판정한다.
    static func isSameIssuer(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = normalizedIssuer(lhs), let right = normalizedIssuer(rhs) else {
            return lhs == rhs
        }
        return left == right
    }

    /// 오퍼 검증의 기준값이 될 Issuer 식별자. 목록 API 값이 http·https URL 이면 그것을(가이드 §3-5),
    /// 아니면(현재 서버는 `did:omn:issuer` 처럼 DID 를 준다) metadata 의 `credential_issuer` 를 쓴다.
    ///
    /// 어느 쪽을 쓰든 신뢰 사슬은 목록 → metadata → 오퍼로 이어진다 — 기준이 되는 metadata 를
    /// 목록이 준 `credentialIssuerMetadataUri` 로 조회했기 때문이다. 서버가 목록 값을 URL 로
    /// 맞추면 코드 변경 없이 목록 값 기준으로 전환된다.
    static func expectedIssuer(listed: String, metadata: IssuerMetadataResponse) -> String {
        normalizedIssuer(listed) != nil ? listed : metadata.credentialIssuer
    }

    /// metadata 가 목록이 지목한 호스트에서 온 것인지 확인 — 기준값이 엉뚱한 호스트의 metadata 로
    /// 정해지는 것을 막는다. 목록 값이 이미 URL 이면(기준값이 목록 값) 확인할 필요가 없어 true.
    static func isMetadataConsistent(metadataUri: String, metadata: IssuerMetadataResponse) -> Bool {
        guard let uriHost = URLComponents(string: metadataUri)?.host?.lowercased(),
              let issuerHost = URLComponents(string: metadata.credentialIssuer)?.host?.lowercased()
        else {
            return false
        }
        return uriHost == issuerHost
    }

    /// http·https URL 을 "scheme://host:port/path" 로 정규화. URL 이 아니면 nil.
    private static func normalizedIssuer(_ value: String) -> String? {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(), !host.isEmpty
        else {
            return nil
        }
        let port = components.port ?? (scheme == "https" ? 443 : 80)
        var path = components.path
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return "\(scheme)://\(host):\(port)\(path)"
    }
}
