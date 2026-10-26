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
    /// Cannot build the start URL because the holder DID or userName (the username given by the registration web view) is missing.
    case missingUserBinding
    /// The user initiation URI does not parse as a URL or has no host.
    case invalidStartURL
    /// The user initiation URI's scheme is not http/https.
    case unsupportedStartScheme
    /// The selected credential configuration id is not in the issuer metadata.
    case unknownConfiguration
    /// The completion redirect does not conform to spec — credential_offer_uri missing / present together with
    /// credential_offer / the decoded result is not an absolute http·https URI.
    case invalidCompletionURI
    /// Attempted to process an already-consumed Credential Offer again (duplicate redirect).
    case offerAlreadyConsumed
}

// MARK: - OID4VCI directory-provider directory + user-initiation WebView integration
//
// Corresponds to §3·§5·§7 of the integration guide ("OID4VCI WebView user claim input integration"). The WebView
// only shows the Issuer's claim-input screen and receives the completion redirect; it performs no Token/Nonce/Proof/
// Credential Request at all — after completion it joins the **same** path as QR/deep-link issuance
// (`IssueOID4VcProtocol`).
//
//   [1] issuers()                directory provider public API → list of active Issuers
//   [2] (app UI) select Issuer → fetch metadata → select credential configuration
//   [3] startURL(...)            WebView start URL carrying did, userName and configuration id
//   [4] (WebView) enter claims → OK → openid-credential-offer:// redirect
//   [5] credentialOfferURI(from:) extract and validate credential_offer_uri from the redirect
//   [6] hand off as-is to the existing issuance path (handleOID4VCI)
//
// No JS bridge is used. Entered claims are stored in the Issuer DB and the app receives only the offer URI.
nonisolated enum OID4VciIssuerDirectory {

    /// Custom scheme of the completion redirect. Only this scheme is treated as the completion response, and it is not handed off to launch an external app.
    static let completionScheme = "openid-credential-offer"

    /// The directory provider's list of OID4VCI-capable Issuers. Called without credentials; no request body or query.
    /// The server returns only Issuers approved as ACTIVE, in ascending order of registration date. Empty array if none.
    static func issuers() async throws -> [OID4VCIIssuerItem] {
        let list: OID4VCIIssuerList = try await CommunicationClient.sendRequest(
            urlString: URLs.TAS_URL + "/list/api/v1/oid4vci/issuers",
            httpMethod: .GET
        )
        return list.items
    }

    /// WebView start URL — `{userInitiationUri}?did=…&userName=…&credential_configuration_id=…`.
    ///
    /// `URLComponents` encodes the query item by item (the whole URL string must not be encoded in one go).
    /// The values carried are the same two, did/userName, as the existing OpenDID issuance web form (`IssueVcProtocol.webFormURL`) —
    /// it was agreed with the server to use `userName` instead of guide §5's `userId`, and the DID is passed along too.
    /// No other values (claims, tokens, Pre-Authorized Code, etc.) are passed in the query.
    ///
    /// - parameter did: holder DID (`WalletState.holderDID`). If unbound, arrives as nil and is rejected.
    /// - parameter userName: user identifier (`WalletState.userName`). Same as above.
    /// - parameter credentialType: passed only when the configuration has multiple identifiers. The current server
    ///   metadata has no `credential_identifiers`, so this is called with nil.
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

    /// Extracts the offer URI from the completion redirect (`openid-credential-offer://?credential_offer_uri=…`).
    ///
    /// Implements guide §7's rejection rules as-is — rejects if `credential_offer` and `credential_offer_uri` are
    /// both present, decoding is done **exactly once** by `URLComponents` (no additional manual
    /// decoding), and rejects if the result is not an absolute http·https URI.
    static func credentialOfferURI(from url: URL) throws -> String {
        guard url.scheme?.lowercased() == completionScheme,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else {
            throw OID4VciDirectoryError.invalidCompletionURI
        }

        // By-value offers (credential_offer) are not used in this integration. If both arrive we cannot tell which one is
        // authoritative, so reject.
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

    /// Issuer identifier equality — compares after normalizing scheme·host·port·path.
    /// Does not use a plain string prefix comparison (guide §8). Default ports (80/443) are treated as omitted.
    ///
    /// If either side is not an http·https URL (e.g. a DID) there is nothing to normalize, so compare by string equality.
    static func isSameIssuer(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = normalizedIssuer(lhs), let right = normalizedIssuer(rhs) else {
            return lhs == rhs
        }
        return left == right
    }

    /// Issuer identifier used as the reference for offer validation. Uses the list API value if it is an http·https URL
    /// (guide §3-5), otherwise (the current server gives a DID like `did:omn:issuer`) the metadata's `credential_issuer`.
    ///
    /// Either way the chain of trust runs list → metadata → offer — because the reference metadata was fetched via
    /// the `credentialIssuerMetadataUri` the list provided. If the server makes the list value a URL, this switches
    /// to the list value as the reference with no code change.
    static func expectedIssuer(listed: String, metadata: IssuerMetadataResponse) -> String {
        normalizedIssuer(listed) != nil ? listed : metadata.credentialIssuer
    }

    /// Checks that the metadata came from the host the list pointed to — prevents the reference value from being
    /// set by metadata from an unrelated host. If the list value is already a URL (the reference is the list value), no check is needed: true.
    static func isMetadataConsistent(metadataUri: String, metadata: IssuerMetadataResponse) -> Bool {
        guard let uriHost = URLComponents(string: metadataUri)?.host?.lowercased(),
              let issuerHost = URLComponents(string: metadata.credentialIssuer)?.host?.lowercased()
        else {
            return false
        }
        return uriHost == issuerHost
    }

    /// Normalizes an http·https URL to "scheme://host:port/path". nil if not a URL.
    static func normalizedIssuer(_ value: String) -> String? {
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
