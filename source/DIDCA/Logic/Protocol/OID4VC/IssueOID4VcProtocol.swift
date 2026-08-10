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

enum IssueOID4VcError: Error {
    case noIssuableCredential
    case invalidCredentialOfferURI
    case preAuthorizedCodeNotFound
    case unsupportedGrantType
    case failedToFetchIssuerMetadata
    case tokenEndpointNotFound
    /// 오퍼의 credential_issuer 가 사용자가 목록에서 고른 Issuer 와 다름 (WebView 발급 전용 검증).
    case issuerMismatch
    /// 오퍼의 credential_configuration_ids 에 사용자가 고른 configuration 이 없음 (WebView 발급 전용 검증).
    case configurationMismatch
}

// MARK: - OID4VCI 발급 흐름
//
// TAS 핸드셰이크(propose/profile/confirm) 기반의 IssueVcProtocol 과 달리 OID4VCI 는
// credential offer → token → credential 3-스텝이고, 진입점을 둘로 나눈다:
//
//   begin(rawPayload:)                     ─ 사용자 입력(tx_code)·인증 전
//     [1] getCredentialOffer         credential_offer_uri GET → CredentialOfferResponse
//
//   process(txCode:passcode:)              ─ tx_code / holder 인증 직후
//     [2] getMetadata                issuer 메타데이터(token/credential 엔드포인트 등)
//     [3] getTokenByPreAuthorizedCode  pre-authorized_code + tx_code → access token
//     [4] requestCredential          holder 키 바인딩 proof 서명 + VC 저장 → 발급 크리덴셜(String)
//
// begin 과 process 사이의 tx_code 입력 모달·holder 인증 시트는 UI 정책이라
// 호출측(AppCoordinator)이 담당한다. 이 타입은 offer 를 노출해 호출측이
// grant type / tx_code 사양을 읽고 모달을 띄울 수 있게 한다.
//
// SDK OID4VCIProtocol 의 6개 API(getCredentialOffer/getMetadata/
// getTokenByPreAuthorizedCode/requestCredential/checkGrantType/getCredentialRequestURL)를
// 이름·시그니처 그대로 이 타입에 static 으로 이식했다. static 들은 상태가 없고
// (인자 in → 결과 out), 인스턴스(offer/metadata)와 orchestration(begin/process)이
// 그 위를 감싼다. 발급 본체(proof 서명·검증·저장)는 여전히 SDK 소관이라
// requestCredential 은 WalletAPI.requestIssueOID4VC 로 위임한다.
nonisolated final class IssueOID4VcProtocol {

    typealias TxCode = CredentialOfferResponse.Grants.PreAuthorizedCode.TxCode

    // MARK: - 단계별 누적 상태
    let offer: CredentialOfferResponse
    private var metadata: IssuerMetadataResponse? = nil

    private init(offer: CredentialOfferResponse) {
        self.offer = offer
    }

    // MARK: - 노출 프로퍼티 (호출측 UI 정책 판단용)

    // v1 은 pre-authorized_code 그랜트만 지원.
    var isPreAuthorized: Bool {
        offer.grants.preAuthorizedCode != nil
    }

    // offer 가 요구하는 tx_code 사양 (없으면 nil → tx_code 입력 불요).
    var txCode: TxCode? {
        offer.grants.preAuthorizedCode?.txCode
    }

    // 발급 대상 credential configuration id (offer 의 첫 항목).
    var configurationId: String? {
        offer.credentialConfigurationIds?.first
    }

    // MARK: - [1] begin
    static func begin(rawPayload: String) async throws -> IssueOID4VcProtocol {
        let offer = try await getCredentialOffer(uri: rawPayload)
        return IssueOID4VcProtocol(offer: offer)
    }

    /// WebView(user-initiated) 발급 전용 오퍼 검증 — 사용자가 목록에서 고른 Issuer·Credential 이
    /// 실제로 돌아온 오퍼와 같은지 확인한다 (연동 가이드 §8).
    ///
    /// QR·딥링크 발급에는 호출하지 않는다. 그쪽은 오퍼 자체가 흐름의 출발점이라 대조할 기준값이 없다.
    /// 오퍼 1회 소비 여부는 발급 세션을 소유한 호출측(AppCoordinator)이 판정한다.
    func validate(expectedIssuer: String, configurationId: String) throws {
        guard OID4VciIssuerDirectory.isSameIssuer(offer.credentialIssuer, expectedIssuer) else {
            throw IssueOID4VcError.issuerMismatch
        }
        guard offer.credentialConfigurationIds?.contains(configurationId) == true else {
            throw IssueOID4VcError.configurationMismatch
        }
        guard isPreAuthorized else {
            throw IssueOID4VcError.unsupportedGrantType
        }
    }

    // MARK: - [2][3][4] process
    //
    // getTokenByPreAuthorizedCode / requestCredential 둘 다 issuer 메타데이터를 요구하므로
    // 발급 전 한 번 조회해 재사용한다. passcode 가 발급 proof 서명 키를 정한다:
    // PIN(nil 아님)→#pin 키, BIO(nil)→#bio 키.
    ///
    /// - parameter txCode: 오퍼가 tx_code 를 요구할 때만 사용자 입력값. 요구하지 않으면 **nil** —
    ///   빈 문자열을 넘기면 `tx_code=` 가 실려 나간다. WebView(user-initiated) 발급은 서버가
    ///   tx_code 없는 Pre-Authorized Code 를 만들므로 항상 nil 이다.
    @discardableResult
    func process(txCode: String?, passcode: String?) async throws -> String {
        guard let configId = configurationId else {
            throw IssueOID4VcError.noIssuableCredential
        }

        let metadata = try await Self.getMetadata(issuerURL: offer.credentialIssuer)
        self.metadata = metadata

        let token = try await Self.requestTokenByPreAuthorizedCode(
            metadata: metadata,
            offer: offer,
            txCode: txCode
        )

        // OID4VCI: token 응답이 authorization_details 를 내려주면 credential_identifier 로 요청해야 한다
        // (configuration id 경로 대신). configId 에 해당하는 항목의 첫 identifier 를 고르고,
        // 없으면 nil → requestCredential 이 credential_configuration_id 경로로 폴백한다.
        let credentialIdentifier = token.authorizationDetails?
            .first { $0.credentialConfigurationId == configId }?
            .credentialIdentifiers?.first

        // requestCredential 이 hWalletToken 필수. 발급 목적의 지갑 토큰 조달.
        let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .ISSUE_VC)

        return try await Self.requestCredential(
            hWalletToken: hWalletToken,
            metadata: metadata,
            token: token,
            passcode: passcode,
            configurationId: configId,
            credentialIdentifier: credentialIdentifier,
            APIGatewayURL: URLs.API_URL
        )
    }
}

// MARK: - 이식한 SDK OID4VCIProtocol API (static · 이름/시그니처 그대로 · 상태 없음)
extension IssueOID4VcProtocol {

    static func getCredentialOffer(uri: String) async throws -> CredentialOfferResponse {
        guard
            let components = URLComponents(string: uri),
            let offerUriValue = components.queryItems?
                .first(where: { $0.name == "credential_offer_uri" })?
                .value
        else {
            throw IssueOID4VcError.invalidCredentialOfferURI
        }

        let offer: CredentialOfferResponse = try await CommunicationClient.sendRequest(
            urlString: offerUriValue,
            httpMethod: .GET
        )

        guard let configIds = offer.credentialConfigurationIds, configIds.isEmpty == false else {
            throw IssueOID4VcError.noIssuableCredential
        }

        return offer
    }

    static func getMetadata(issuerURL: String) async throws -> IssuerMetadataResponse {
        try await getMetadata(metadataURI: issuerURL + "/.well-known/openid-credential-issuer")
    }

    /// well-known 경로가 이미 붙은 완성 URI 로 조회한다. 목록사업자가 내려주는
    /// `credentialIssuerMetadataUri` 가 이 형태라, issuer URL 에 경로를 덧붙이는 위 오버로드를 쓰면
    /// well-known 이 두 번 붙는다.
    static func getMetadata(metadataURI: String) async throws -> IssuerMetadataResponse {
        let meta: IssuerMetadataResponse = try await CommunicationClient.sendRequest(
            urlString: metadataURI,
            httpMethod: .GET
        )
        return meta
    }

    static func requestTokenByPreAuthorizedCode(
        metadata: IssuerMetadataResponse,
        offer: CredentialOfferResponse,
        txCode: String?
    ) async throws -> TokenResponse {
        if case try checkGrantType(offer: offer) = .authorizationCode {
            throw IssueOID4VcError.unsupportedGrantType
        }

        @ValidURL var endPoint: String

        if let authServers = metadata.authorizationServers, authServers.isEmpty == false {
            endPoint = authServers.first!
        } else if let tokenEndpoint = metadata.tokenEndpoint, tokenEndpoint.isEmpty == false {
            endPoint = tokenEndpoint
        } else {
            endPoint = offer.credentialIssuer
        }

        let tokenEndpoint = try await getCredentialRequestURL(url: endPoint)

        guard let configIds = offer.credentialConfigurationIds, configIds.isEmpty == false else {
            throw IssueOID4VcError.noIssuableCredential
        }

        let authDetailsArray = configIds.map {
            AuthorizationDetails(credentialConfigurationId: $0, credentialIdentifiers: nil)
        }

        let tokenRequest = TokenRequest(
            preAuthorizedCode: offer.grants.preAuthorizedCode!.preAuthorizedCode,
            txCode: txCode,
            authorizationDetails: authDetailsArray
        )

        let response: TokenResponse = try await CommunicationClient.sendPostUrlencoded(
            urlString: tokenEndpoint,
            requestJsonable: tokenRequest
        )

        return response
    }

    static func requestCredential(
        hWalletToken: String,
        metadata: IssuerMetadataResponse,
        token: TokenResponse,
        passcode: String?,
        configurationId: String,
        credentialIdentifier: String?,
        APIGatewayURL: String
    ) async throws -> String {
        try await WalletAPI.shared.requestIssueOID4VC(
            hWalletToken: hWalletToken,
            metadata: metadata,
            token: token,
            passcode: passcode,
            configurationId: configurationId,
            credentialIdentifier: credentialIdentifier,
            APIGatewayURL: APIGatewayURL
        )
    }

    private enum AuthorizationGrantType {
        case preAuthorizedCode
        case authorizationCode
    }

    private static func checkGrantType(offer: CredentialOfferResponse) throws -> AuthorizationGrantType {
        if let preAuth = offer.grants.preAuthorizedCode {
            if preAuth.preAuthorizedCode.isEmpty {
                throw IssueOID4VcError.preAuthorizedCodeNotFound
            }
            return .preAuthorizedCode
        } else if let _ = offer.grants.authorizationCode {
            return .authorizationCode
        } else {
            throw IssueOID4VcError.unsupportedGrantType
        }
    }

    private static func getCredentialRequestURL(url: String) async throws -> String {
        @ValidURL var issuerURL = url
        let subURL = ".well-known/oauth-authorization-server"

        let (result, status) = try await CommunicationClient.sendRequest(
            urlString: _issuerURL.appendingPath(subURL),
            httpMethod: .GET
        )

        if status != 200 {
            throw IssueOID4VcError.failedToFetchIssuerMetadata
        }

        let json = try JSONSerialization.jsonObject(with: result, options: []) as? [String: Any]
        guard let endPoint = json?["token_endpoint"], let tokenEndpoint = endPoint as? String else {
            throw IssueOID4VcError.tokenEndpointNotFound
        }

        return tokenEndpoint
    }
}
