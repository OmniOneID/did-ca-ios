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

nonisolated enum TASConnection {
    // Applied immediately on save — not cached; read on every request.
    static var host: String { URLs.TAS_URL }
}

// MARK: - User Registration
extension TASConnection {

    /// Starts the user registration transaction. The response txId is used as the correlation key for later steps.
    static func initiateUserRegistration() async throws -> String {
        let urlString = host + "/tas/api/v1/propose-register-user"
        let request = ProposeRegisterUser(id: UUID().uuidString)
        let response: _ProposeRegisterUser = try await HttpClient.sendPostRequest(
            urlString: urlString,
            request: request
        )
        return response.txId
    }

    /// KYC lookup request for PII verification. kycTxId = the userId received from the onboarding registration web view.
    static func retrieveKYC(request: RetrieveKyc) async throws {
        let urlString = host + "/tas/api/v1/retrieve-kyc"
        let _: _RetrieveKyc = try await HttpClient.sendPostRequest(
            urlString: urlString,
            request: request
        )
    }

    /// Confirms user registration. Called right after requestRegisterUser.
    static func confirmUserRegistration(txId: String, serverToken: String) async throws {
        let urlString = host + "/tas/api/v1/confirm-register-user"
        let request = ConfirmRegisterUser(id: UUID().uuidString, txId: txId, serverToken: serverToken)
        let _: _ConfirmRegisterUser = try await HttpClient.sendPostRequest(
            urlString: urlString,
            request: request
        )
    }
}

// MARK: - DID Document Update (updates the holder document when BIO is added/removed in Settings)
extension TASConnection {

    /// Starts the document update transaction. did = holder DID id. The response txId / authNonce are inputs to later steps.
    static func proposeUpdateDidDoc(did: String) async throws -> _ProposeUpdateDidDoc {
        let urlString = host + "/tas/api/v1/propose-update-diddoc"
        let request = ProposeUpdateDidDoc(id: UUID().uuidString, did: did)
        return try await HttpClient.sendPostRequest(urlString: urlString, request: request)
    }

    /// Confirms the document update. Called right after WalletAPI.shared.requestUpdateUser.
    static func confirmUpdateDidDoc(txId: String, serverToken: String) async throws {
        let urlString = host + "/tas/api/v1/confirm-update-diddoc"
        let request = ConfirmUpdateDidDoc(id: UUID().uuidString, txId: txId, serverToken: serverToken)
        let _: _ConfirmUpdateDidDoc = try await HttpClient.sendPostRequest(
            urlString: urlString,
            request: request
        )
    }
}

// MARK: - Token / ECDH
extension TASConnection {

    /// Requests the encryption container for server token generation (encStd / iv).
    static func createToken(request: RequestCreateToken) async throws -> _RequestCreateToken {
        let urlString = host + "/tas/api/v1/request-create-token"
        return try await HttpClient.sendPostRequest(urlString: urlString, request: request)
    }

    /// ECDH key exchange (response with server nonce and public key for deriving sharedSecret).
    static func requestEcdh(request: RequestEcdh) async throws -> _RequestEcdh {
        let urlString = host + "/tas/api/v1/request-ecdh"
        return try await HttpClient.sendPostRequest(urlString: urlString, request: request)
    }
}

// Issuance routing mode. If plan.issuanceMode is .DIRECT/absent, go directly to TAS; if .PROXY, go via the issuer proxy.
enum IssuanceMode {
    case tas
    case proxy(urlString: String)
}

// MARK: - VC Issuance
extension TASConnection {

    /// Base host per issuance mode. For proxy, the issuer endpoint + "/proxy"; otherwise TAS.
    nonisolated static func routeHost(mode: IssuanceMode) -> String {
        switch mode {
        case .tas:                  return host + "/tas"
        case .proxy(let urlString): return urlString + "/proxy"
        }
    }

    /// List of issuable VC plans. The menu source the user picks from in "From list".
    /// primary / secondary are attached as `tags[]=...` queries for backend-side plan filtering.
    /// DIDCA currently receives the full list unfiltered, but the signature matches CampusID for future use.
    static func getVCPlanList(
        primary: String? = nil,
        secondary: String? = nil
    ) async throws -> [VCPlan] {
        var urlString = host + "/list/api/v1/vcplan/list"
        if let primary {
            urlString += "?tags%5B%5D=\(primary)"
            if let secondary {
                urlString += "&tags%5B%5D=\(secondary)"
            }
        }
        let response: VCPlanList = try await HttpClient.sendGetRequest(urlString: urlString)
        return response.items
    }

    /// Starts the issuance transaction. The response txId is the correlation key for later steps; refId is input to requestIssueVc.
    static func proposeIssueVc(mode: IssuanceMode = .tas, request: ProposeIssueVc) async throws -> _ProposeIssueVc {
        let urlString = routeHost(mode: mode) + "/api/v1/propose-issue-vc"
        return try await HttpClient.sendPostRequest(urlString: urlString, request: request)
    }

    /// Fetches the issuer profile + authNonce. The authNonce goes into getSignedDidAuth.
    static func requestIssueProfile(mode: IssuanceMode = .tas, request: RequestIssueProfile) async throws -> _RequestIssueProfile {
        let urlString = routeHost(mode: mode) + "/api/v1/request-issue-profile"
        return try await HttpClient.sendPostRequest(urlString: urlString, request: request)
    }

    /// Confirms issuance. Called after WalletAPI.shared.requestIssueVc — vcId is the value received there.
    static func confirmIssueVc(mode: IssuanceMode = .tas, request: ConfirmIssueVc) async throws -> _ConfirmIssueVc {
        let urlString = routeHost(mode: mode) + "/api/v1/confirm-issue-vc"
        return try await HttpClient.sendPostRequest(urlString: urlString, request: request)
    }
}

// MARK: - VC Revocation
extension TASConnection {

    /// Starts the revocation transaction. The response txId / issuerNonce / authType are inputs to later steps.
    /// host is the base decided by RevokeVcProtocol (the proxy issuer endpoint or TAS).
    static func proposeRevokeVc(host: String, request: ProposeRevokeVc) async throws -> _ProposeRevokeVc {
        let urlString = host + "/api/v1/propose-revoke-vc"
        return try await HttpClient.sendPostRequest(urlString: urlString, request: request)
    }
}
