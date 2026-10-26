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

// MARK: - VC revocation flow (OpenDID SDK usage example)
//
// The entry point is split into two stages:
//
//   preProcess(vcId:)                      ─ before user authentication
//     [1] propose-revoke-vc        tell TAS/issuer of the intent to revoke → txId/issuerNonce/authType
//     [2] ECDH                     only on the direct TAS path — derive sharedSecret
//     [3] request-server-token     only on the direct TAS path — hServerToken
//
//   process(passcode:)                     ─ right after user PIN/BIO authentication
//     [4] request-revoke-vc        revocation request authenticated with the wallet key
//     [5] confirm-revoke-vc        confirm revocation completed
//
// The static entry point RevokeVcProtocol.revoke(vcId:passcode:) bundles walletToken issuance →
// shortcut branch on server status (.REVOKED) → preProcess + process → wallet deletion into a
// single call.
//
// Routing:
//   - proxy-issued (`Preference.getIssuerEndpoint(forVcId:)` exists) → straight to the issuer,
//     skipping the ECDH/serverToken stages
//   - otherwise → via TAS (`.tas`), performing ECDH/serverToken
//
// If there is a paired ZKP, `WalletAPI.deleteCredentials` deletes it too, so the VC
// revocation call alone is enough.
//
// Pattern source: did-ca-ios `RevokeVcProtocol` (CommonProtocol singleton).
nonisolated final class RevokeVcProtocol {

    // MARK: - Routing (specified by the caller)
    private let host: String
    private let isTas: Bool
    private let hWalletToken: String

    // MARK: - State accumulated across stages
    private var vcId: String = ""
    private var hServerToken: String? = nil
    private var sharedSecret: Data? = nil
    private var txId: String = ""
    private var issuerNonce: String = ""
    // OptionSet — left as an empty set until the propose response fills it.
    private var authType: VerifyAuthType = []

    init(host: String, isTas: Bool, hWalletToken: String) {
        self.host = host
        self.isTas = isTas
        self.hWalletToken = hWalletToken
    }

    // MARK: - [1] propose-revoke-vc
    @discardableResult
    private func proposeRevokeVc(vcId: String) async throws -> _ProposeRevokeVc {
        let request = ProposeRevokeVc(id: UUID().uuidString, vcId: vcId)
        let response = try await TASConnection.proposeRevokeVc(host: host, request: request)
        self.vcId = vcId
        self.txId = response.txId
        self.issuerNonce = response.issuerNonce
        self.authType = response.authType
        return response
    }

    // MARK: - [2] ECDH — derive sharedSecret from the holder DID (TAS only)
    private func deriveSharedSecret() async throws {
        self.sharedSecret = try await TokenGenerator.getSharedSecret(type: .holder, txId: txId)
    }

    // MARK: - [3] request-server-token (TAS only, needs sharedSecret)
    private func requestServerToken() async throws {
        guard let sharedSecret else { return }
        self.hServerToken = try await TokenGenerator.requestServerToken(
            purpose: .REMOVE_VC,
            txId: txId,
            sharedSecret: sharedSecret
        )
    }

    // MARK: - [4] request-revoke-vc
    private func requestRevokeVc(passcode: String?) async throws {
        let response = try await WalletAPI.shared.requestRevokeVc(
            hWalletToken: hWalletToken,
            url: host + "/api/v1/request-revoke-vc",
            authType: authType,
            vcId: vcId,
            issuerNonce: issuerNonce,
            txId: txId,
            serverToken: hServerToken,
            passcode: passcode
        )
        // Latest txId from the request-revoke-vc response — used in the confirm stage.
        self.txId = response.txId
    }

    // MARK: - [5] confirm-revoke-vc
    private func confirmRevokeVc() async throws {
        let request = ConfirmRevokeVc(
            id: UUID().uuidString,
            txId: txId,
            serverToken: hServerToken
        )
        try await HttpClient.sendPostRequest(
            urlString: host + "/api/v1/confirm-revoke-vc",
            request: request
        )
    }

    // MARK: - Entry point: stages before user authentication (1 ~ 3)
    func preProcess(vcId: String) async throws {
        try await proposeRevokeVc(vcId: vcId)
        if isTas {
            try await deriveSharedSecret()
            try await requestServerToken()
        }
    }

    // MARK: - Entry point: stages after user authentication (4 ~ 5)
    func process(passcode: String?) async throws {
        try await requestRevokeVc(passcode: passcode)
        try await confirmRevokeVc()
    }
}

// MARK: - Static convenience
extension RevokeVcProtocol {

    /// Revoke a VC — bundles walletToken issuance → .REVOKED shortcut branch → preProcess + process → wallet deletion into one call.
    /// passcode is the entered value for PIN authentication, nil for BIO (when the SDK uses the bio key, the system shows the prompt).
    static func revoke(vcId: String, passcode: String?) async throws {
        let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .REMOVE_VC)

        // Revocation depends on the current server status, so ignore the cache and look it up fresh.
        // A VC already revoked (.REVOKED) → skip the server protocol and delete it from the wallet directly.
        if (try? await CredentialStore.shared.status(forVcId: vcId, forceRefresh: true)) == .REVOKED {
            try deleteFromWallet(vcId: vcId, hWalletToken: hWalletToken)
            return
        }

        let (host, isTas) = revokeRoute(forVcId: vcId)
        let proto = RevokeVcProtocol(host: host, isTas: isTas, hWalletToken: hWalletToken)
        try await proto.preProcess(vcId: vcId)
        try await proto.process(passcode: passcode)
        try deleteFromWallet(vcId: vcId, hWalletToken: hWalletToken)
    }

    /// Actually delete the VC from the wallet (the paired ZKP is deleted too) + clean up the issuer endpoint mapping.
    private static func deleteFromWallet(vcId: String, hWalletToken: String) throws {
        _ = try WalletAPI.shared.deleteCredentials(hWalletToken: hWalletToken, ids: [vcId])
        Preference.removeIssuerEndpoint(forVcId: vcId)
    }

    /// Revocation routing — for proxy-issued VCs, the endpoint stored at issuance; otherwise TAS.
    /// `isTas` determines whether the serverToken (ECDH) stage is performed.
    private static func revokeRoute(forVcId vcId: String) -> (host: String, isTas: Bool) {
        if let endpoint = Preference.getIssuerEndpoint(forVcId: vcId), !endpoint.isEmpty {
            return (endpoint, false)
        }
        return (TASConnection.routeHost(mode: .tas), true)
    }
}
