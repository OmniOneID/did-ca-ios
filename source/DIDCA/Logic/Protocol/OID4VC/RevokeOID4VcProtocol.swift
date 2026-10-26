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

enum RevokeOID4VcError: Error {
    case credentialNotFound
}

// MARK: - RevokeOID4VcProtocol
//
// Deletes OID4VCI-issued credentials (SD-JWT, mDoc). Server revocation is handled by SDK `requestRevokeOID4VC`
// (c_nonce from nonce_endpoint → sign revocation JWT → POST to credential_revocation_endpoint).
// The app handles what surrounds it — which issuer to send to, which auth is needed, local deletion on success.
//
// Split into two steps. The auth method is determined by the credential's binding key, so the auth UI sits in between.
//   [1] route    issuer record → fetch metadata → decide server-revocability and binding key (before auth)
//   [2] revoke   REMOVE_VC token → requestRevokeOID4VC → deleteOID4VCs → remove issuer record (after auth)
//
// The two cases where server revocation is impossible are deleted locally without auth, as before (`deleteLocally`).
//   - no issuer record: a credential issued before this feature existed
//   - no credential_revocation_endpoint in metadata: the issuer does not support revocation
// Any other failure (metadata fetch failure, server rejection, credential lacks a status list, etc.) throws — the
// caller shows the error and keeps the card. Calling the same API again is safe (a fresh nonce each time, and the
// server returns 200 even for an already-revoked credential).
nonisolated enum RevokeOID4VcProtocol {

    enum Route {
        /// Server revocation possible — pick the auth method from `bindingKeyId`, then call `revoke`.
        case server(metadata: IssuerMetadataResponse, bindingKeyId: String)
        /// Server revocation not possible — delete via `deleteLocally` without auth.
        case localOnly
    }

    // MARK: - [1] route
    static func route(credentialId: String) async throws -> Route {
        guard let credentialIssuer = OID4VcIssuerStore.issuer(forCredentialId: credentialId) else {
            return .localOnly
        }
        let metadata = try await IssueOID4VcProtocol.getMetadata(issuerURL: credentialIssuer)
        guard let endpoint = metadata.credentialRevocationEndpoint, !endpoint.isEmpty else {
            return .localOnly
        }
        return .server(metadata: metadata, bindingKeyId: try await bindingKeyId(of: credentialId))
    }

    // MARK: - [2] revoke
    /// - parameter passcode: PIN if the binding key is #pin, nil if #bio (the SDK shows the biometric prompt).
    static func revoke(credentialId: String,
                       metadata: IssuerMetadataResponse,
                       passcode: String?) async throws {
        let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .REMOVE_VC)
        try await WalletAPI.shared.requestRevokeOID4VC(
            hWalletToken: hWalletToken,
            metadata: metadata,
            vcId: credentialId,
            passcode: passcode
        )
        try deleteFromWallet(credentialId: credentialId, hWalletToken: hWalletToken)
    }

    /// Deletes from the wallet only, without server revocation.
    static func deleteLocally(credentialId: String) async throws {
        let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .REMOVE_VC)
        try deleteFromWallet(credentialId: credentialId, hWalletToken: hWalletToken)
    }

    // MARK: - Internal

    /// Binding key fixed at issuance (`pin`/`bio`) — the revocation JWT is also signed with this key.
    private static func bindingKeyId(of credentialId: String) async throws -> String {
        let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .DETAIL_VC)
        let items = try WalletAPI.shared.getOID4VCs(hWalletToken: hWalletToken, ids: [credentialId])
        switch items.first {
        case let item as SdJwtCredentialItem: return item.kid
        case let item as MdocCredentialItem:  return item.kid
        default: throw RevokeOID4VcError.credentialNotFound
        }
    }

    private static func deleteFromWallet(credentialId: String, hWalletToken: String) throws {
        try WalletAPI.shared.deleteOID4VCs(hWalletToken: hWalletToken, ids: [credentialId])
        OID4VcIssuerStore.remove(credentialId: credentialId)
    }
}
