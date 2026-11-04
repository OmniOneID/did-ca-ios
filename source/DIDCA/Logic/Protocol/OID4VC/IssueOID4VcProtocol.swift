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
    /// The offer's credential_issuer differs from the Issuer the user picked from the list (WebView-issuance-only check).
    case issuerMismatch
    /// The offer's credential_configuration_ids does not contain the configuration the user picked (WebView-issuance-only check).
    case configurationMismatch
    /// Failure in the **token request** step — wraps the underlying error as-is.
    ///
    /// Marked separately because the design spec applies the `"Wrong code."` fallback **only to this step**.
    /// Without this marker, failures in metadata fetch, wallet token, or credential request would all read as "wrong code".
    case tokenRequestFailed(Error)
    /// `requestCredential(passcode:)` was called before `requestToken(txCode:)` succeeded — call-order error.
    case tokenNotRequested
}

// MARK: - OID4VCI issuance flow
//
// Unlike IssueVcProtocol, which is based on the TAS handshake (propose/profile/confirm), OID4VCI is
// a 3-step credential offer → token → credential flow, split into three entry points:
//
//   begin(rawPayload:)                     ─ before user input (tx_code) and auth
//     [1] getCredentialOffer         credential_offer_uri GET → CredentialOfferResponse
//
//   requestToken(txCode:)                  ─ right after tx_code input, before holder auth
//     [2] getMetadata                issuer metadata (token/credential endpoints, etc.)
//     [3] getTokenByPreAuthorizedCode  pre-authorized_code + tx_code → access token
//
//   requestCredential(passcode:)           ─ right after holder auth
//     [4] requestCredential          sign holder key-binding proof + store VC → issued credential (String)
//
// Why the token is obtained before auth: the tx_code verdict only comes from the token response.
// If deferred until after auth, a user who entered the wrong code would only see the error after also entering a PIN.
//
// The tx_code input modal and holder auth sheet between steps are UI policy, so
// the caller (AppCoordinator) handles them. This type exposes the offer so the caller can
// read the grant type / tx_code spec and present the modal.
//
// The 6 APIs of SDK OID4VCIProtocol (getCredentialOffer/getMetadata/
// getTokenByPreAuthorizedCode/requestCredential/checkGrantType/getCredentialRequestURL) were
// ported into this type as statics with the same names and signatures. The statics are stateless
// (args in → result out), and the instance (offer/metadata/token) and orchestration (begin/requestToken/
// requestCredential)
// wrap them. The issuance core (proof signing, verification, storage) is still the SDK's job, so
// requestCredential delegates to WalletAPI.requestIssueOID4VC.
nonisolated final class IssueOID4VcProtocol {

    typealias TxCode = CredentialOfferResponse.Grants.PreAuthorizedCode.TxCode

    // MARK: - State accumulated per step
    let offer: CredentialOfferResponse
    private var metadata: IssuerMetadataResponse? = nil
    private var token: TokenResponse? = nil

    private init(offer: CredentialOfferResponse) {
        self.offer = offer
    }

    // MARK: - Exposed properties (for the caller's UI policy decisions)

    // v1 supports only the pre-authorized_code grant.
    var isPreAuthorized: Bool {
        offer.grants.preAuthorizedCode != nil
    }

    // tx_code spec required by the offer (nil if none → no tx_code input needed).
    var txCode: TxCode? {
        offer.grants.preAuthorizedCode?.txCode
    }

    // Credential configuration id to issue (the offer's first entry).
    var configurationId: String? {
        offer.credentialConfigurationIds?.first
    }

    // MARK: - [1] begin
    static func begin(rawPayload: String) async throws -> IssueOID4VcProtocol {
        let offer = try await getCredentialOffer(uri: rawPayload)
        return IssueOID4VcProtocol(offer: offer)
    }

    /// Offer validation for WebView (user-initiated) issuance only — checks that the Issuer and Credential the user
    /// picked from the list match the offer that actually came back (integration guide §8).
    ///
    /// Not called for QR/deep-link issuance. There the offer itself is the flow's starting point, so there is no reference to compare against.
    /// Whether the offer has already been consumed once is decided by the caller that owns the issuance session (AppCoordinator).
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

    // MARK: - [2][3] requestToken
    //
    // getTokenByPreAuthorizedCode and requestCredential both require issuer metadata, so
    // fetch it once here, keep it alongside the token, and requestCredential reuses it.
    ///
    /// - parameter txCode: user input, only when the offer requires tx_code. If not required, **nil** —
    ///   passing an empty string sends `tx_code=`. WebView (user-initiated) issuance is always nil, since the server
    ///   creates a Pre-Authorized Code without tx_code.
    func requestToken(txCode: String?) async throws {
        guard configurationId != nil else {
            throw IssueOID4VcError.noIssuableCredential
        }

        let metadata = try await Self.getMetadata(issuerURL: offer.credentialIssuer)

        // The tx_code verdict applies only to the token POST response — so only that one call
        // is wrapped inside `requestTokenByPreAuthorizedCode` to surface as `tokenRequestFailed`.
        // Failures in the preparation steps pass straight through here and are treated as general issuance failures.
        let token = try await Self.requestTokenByPreAuthorizedCode(
            metadata: metadata,
            offer: offer,
            txCode: txCode
        )

        self.metadata = metadata
        self.token = token
    }

    // MARK: - [4] requestCredential
    //
    // Call only after requestToken has finished. The passcode decides the issuance proof signing key:
    // PIN (non-nil) → #pin key, BIO (nil) → #bio key.
    @discardableResult
    func requestCredential(passcode: String?) async throws -> String {
        guard let configId = configurationId else {
            throw IssueOID4VcError.noIssuableCredential
        }
        guard let metadata, let token else {
            throw IssueOID4VcError.tokenNotRequested
        }

        // OID4VCI: if the token response returns authorization_details, the request must use credential_identifier
        // (instead of the configuration id path). Pick the first identifier of the entry matching configId;
        // if none, nil → requestCredential falls back to the credential_configuration_id path.
        let credentialIdentifier = token.authorizationDetails?
            .first { $0.credentialConfigurationId == configId }?
            .credentialIdentifiers?.first

        // requestCredential requires hWalletToken. Obtain a wallet token for issuance.
        let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .ISSUE_VC)

        let credentialId = try await Self.requestCredential(
            hWalletToken: hWalletToken,
            metadata: metadata,
            token: token,
            passcode: passcode,
            configurationId: configId,
            credentialIdentifier: credentialIdentifier,
            APIGatewayURL: URLs.API_URL
        )

        // Recorded so the same issuer metadata can be fetched again at revocation — exactly the raw value used for the metadata fetch.
        OID4VcIssuerStore.register(credentialIssuer: offer.credentialIssuer, forCredentialId: credentialId)
        return credentialId
    }
}

// MARK: - Ported SDK OID4VCIProtocol API (static · same names/signatures · stateless)
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

    /// Fetches using a complete URI that already has the well-known path. The `credentialIssuerMetadataUri`
    /// given by the directory provider has this form, so using the overload above (which appends the path to the issuer URL)
    /// would append well-known twice.
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

        // The only point where the tx_code verdict applies is **this POST's response**. The preparation steps above
        // (grant type check, endpoint validation, authorization server metadata fetch, issuance target check) are
        // unrelated to the code, so they are not wrapped in `tokenRequestFailed` — wrapping them would show
        // "Wrong code." to a user who entered the correct code.
        do {
            let response: TokenResponse = try await CommunicationClient.sendPostUrlencoded(
                urlString: tokenEndpoint,
                requestJsonable: tokenRequest
            )
            return response
        } catch {
            throw IssueOID4VcError.tokenRequestFailed(error)
        }
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
