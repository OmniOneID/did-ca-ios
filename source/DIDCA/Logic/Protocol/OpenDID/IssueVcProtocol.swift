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

enum IssueVcError: Error {
    case missingIssueResponse
    case noAllowedIssuer
    case missingProxyEndpoint
    case invalidWebFormURL
    /// No username was provided by the registration web view, so the user name can't be put in the issuance web form.
    case missingUserName
    case missingProfile
    case missingVcId
}

// MARK: - VC issuance flow (OpenDID SDK usage example)
//
// The entry point is split into two stages:
//
//   preProcess(vcPlanId:issuer:offerId:)   ─ before user authentication
//     [1] propose-issue-vc          tell TAS of the intent to issue → txId/refId
//     [2] (parallel) request-wallet-token
//     [3] ECDH                      only in .tas mode — derive sharedSecret
//     [4] request-server-token      only in .tas mode — hServerToken
//     [5] request-issue-profile     receive issuer profile + authNonce
//
//   process(passcode:)                     ─ right after user PIN/BIO authentication
//     [6] getSignedDidAuth          sign authNonce with the holder DID key (sync)
//     [7] request-issue-vc          request the VC with the signed didAuth + token → vcId
//     [8] confirm-issue-vc          confirm issuance completed
//
// Static entry points that call both stages back to back are also provided for convenience:
//   IssueVcProtocol.issue(plan:passcode:)
//   IssueVcProtocol.issue(offer:passcode:)
//
// Pattern source: did-ca-ios (UIKit reference) — one HTTP call = one private
// method; instance state (txId/hServerToken/issueProfile/vcId) is carried between
// stages so the orchestration function bodies (preProcess/process) read like a script.
nonisolated final class IssueVcProtocol {

    // MARK: - Routing mode (.tas / .proxy)
    private let mode: IssuanceMode

    // MARK: - State accumulated across stages
    private var txId: String = ""
    private var refId: String = ""
    private var hWalletToken: String = ""
    private var hServerToken: String? = nil
    private var sharedSecret: Data? = nil
    private var issueProfile: _RequestIssueProfile? = nil
    private var vcId: String? = nil

    init(mode: IssuanceMode) {
        self.mode = mode
    }

    // MARK: - [1] propose-issue-vc
    @discardableResult
    private func proposeIssueVc(
        vcPlanId: String,
        issuer: String,
        offerId: String?
    ) async throws -> _ProposeIssueVc {
        let request = ProposeIssueVc(
            id: UUID().uuidString,
            vcPlanId: vcPlanId,
            issuer: issuer,
            offerId: offerId
        )
        let response = try await TASConnection.proposeIssueVc(mode: mode, request: request)
        self.txId = response.txId
        self.refId = response.refId
        return response
    }

    // MARK: - [3] ECDH — derive sharedSecret from the holder DID (.tas only)
    private func deriveSharedSecret() async throws {
        self.sharedSecret = try await TokenGenerator.getSharedSecret(type: .holder, txId: txId)
    }

    // MARK: - [4] request-server-token (.tas only, needs sharedSecret)
    private func requestServerToken() async throws {
        guard let sharedSecret else { return }
        self.hServerToken = try await TokenGenerator.requestServerToken(
            purpose: .ISSUE_VC,
            txId: txId,
            sharedSecret: sharedSecret
        )
    }

    // MARK: - [2] request-wallet-token
    private func requestWalletToken() async throws {
        self.hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .ISSUE_VC)
    }

    // MARK: - [5] request-issue-profile
    private func requestIssueProfile() async throws {
        // .tas identifies the user by the serverToken obtained via ECDH, but .proxy has no serverToken
        // handshake, so it identifies the user by userId instead of serverToken.
        let request: RequestIssueProfile
        if case .proxy = mode {
            request = RequestIssueProfile(
                id: UUID().uuidString,
                txId: txId,
                userId: Preference.getUserId()
            )
        } else {
            request = RequestIssueProfile(
                id: UUID().uuidString,
                txId: txId,
                serverToken: hServerToken
            )
        }
        let response = try await TASConnection.requestIssueProfile(mode: mode, request: request)
        self.issueProfile = response
        // Update to the latest txId from the profile response — used in the request-issue-vc stage.
        self.txId = response.txId
    }

    // MARK: - [6][7] getSignedDidAuth + request-issue-vc
    private func requestIssueVc(passcode: String?) async throws {
        guard let profile = issueProfile else {
            throw IssueVcError.missingProfile
        }
        let didAuth = try WalletAPI.shared.getSignedDidAuth(
            authNonce: profile.authNonce,
            passcode: passcode
        )
        let (vcId, response) = try await WalletAPI.shared.requestIssueVc(
            url: TASConnection.routeHost(mode: mode) + "/api/v1/request-issue-vc",
            hWalletToken: hWalletToken,
            didAuth: didAuth,
            issuerProfile: profile,
            refId: refId,
            serverToken: hServerToken,
            APIGatewayURL: URLs.API_URL
        )
        guard let response else {
            throw IssueVcError.missingIssueResponse
        }
        self.vcId = vcId
        // Latest txId from the requestIssueVc response — may differ from the one in the propose stage.
        self.txId = response.txId
    }

    // MARK: - [8] confirm-issue-vc
    private func confirmIssueVc() async throws {
        guard let vcId else {
            throw IssueVcError.missingVcId
        }
        let request = ConfirmIssueVc(
            id: UUID().uuidString,
            txId: txId,
            serverToken: hServerToken,
            vcId: vcId
        )
        _ = try await TASConnection.confirmIssueVc(mode: mode, request: request)
    }

    // MARK: - Entry point: stages before user authentication (1 ~ 5)
    func preProcess(vcPlanId: String, issuer: String, offerId: String?) async throws {
        try await proposeIssueVc(vcPlanId: vcPlanId, issuer: issuer, offerId: offerId)

        // walletToken is independent of sharedSecret/serverToken/profile — runs concurrently in the background.
        async let walletTokenTask: () = requestWalletToken()

        // serverToken (ECDH-based) is needed only for direct TAS issuance. For proxy the issuer handles it itself.
        if case .tas = mode {
            try await deriveSharedSecret()
            try await requestServerToken()
        }

        try await requestIssueProfile()
        try await walletTokenTask
    }

    // MARK: - Entry point: stages after user authentication (6 ~ 8) + post-processing
    @discardableResult
    func process(passcode: String?) async throws -> String {
        try await requestIssueVc(passcode: passcode)
        try await confirmIssueVc()

        // If issued via proxy, store the issuer endpoint keyed by vcId — on revocation the host is looked up by vcId.
        if case .proxy = mode, let vcId {
            Preference.setIssuerEndpoint(TASConnection.routeHost(mode: mode), forVcId: vcId)
        }

        guard let vcId else {
            throw IssueVcError.missingVcId
        }
        return vcId
    }
}

// MARK: - Static convenience
//
// A single entry point that calls preProcess + process back to back. The current UX takes user
// authentication *before* the SDK handshake, so there's no need to split the two stages and this
// static method allows a single call. If UI such as checking the issuer profile has to go between
// the two stages, call the instance API (preProcess → process) directly.
extension IssueVcProtocol {

    // Manual issuance — routing decided by plan.allowedIssuers / issuanceMode / endpoints.
    @discardableResult
    static func issue(plan: VCPlan, passcode: String?) async throws -> String {
        let proto = try await begin(plan: plan)
        return try await proto.process(passcode: passcode)
    }

    // Returns an instance that has run only up to preProcess (propose-issue-vc etc.) — use it when, as in
    // the did-ca order, UI such as a web form / authentication must go between preProcess and process.
    // propose runs first to create the issuance transaction (txId), and addVcInfo is then layered on top of it.
    static func begin(plan: VCPlan) async throws -> IssueVcProtocol {
        guard let issuer = plan.allowedIssuers?.first else {
            throw IssueVcError.noAllowedIssuer
        }
        let mode = try issuanceMode(of: plan)
        let proto = IssueVcProtocol(mode: mode)
        try await proto.preProcess(vcPlanId: plan.vcPlanId, issuer: issuer, offerId: nil)
        return proto
    }

    // QR issuance — straight to TAS using only the offer's vcPlanId/issuer/offerId. No plan list
    // lookup (did-ca-ios pattern): the SDK response has no issuanceMode, so the client can't
    // branch. PROXY-mode plan issuance is exclusive to the manual Add VC path (issue(plan:)).
    @discardableResult
    static func issue(offer: IssueOfferPayload, passcode: String?) async throws -> String {
        let proto = IssueVcProtocol(mode: .tas)
        try await proto.preProcess(
            vcPlanId: offer.vcPlanId,
            issuer: offer.issuer,
            offerId: offer.offerId
        )
        return try await proto.process(passcode: passcode)
    }

    // Issuance additional-info web form URL — DEMO_URL/addVcInfo?did=&userName=&vcSchemaId=.
    // Puts the holder DID id, userName (WalletState — same value as OID4VCI user initiation) and the plan's
    // schema id in the query. The schema id may be of the form "...?id=<value>", so take the part after '='.
    static func webFormURL(for plan: VCPlan) throws -> URL {
        let holderDid = try WalletAPI.shared.getDidDocument(type: .HolderDidDocumnet).id
        guard let userName = WalletState.userName else {
            throw IssueVcError.missingUserName
        }
        let schemaId = plan.credentialSchema.id.components(separatedBy: "=").last
            ?? plan.credentialSchema.id

        var components = URLComponents(string: URLs.DEMO_URL + "/addVcInfo")
        components?.queryItems = [
            URLQueryItem(name: "did", value: holderDid),
            URLQueryItem(name: "userName", value: userName),
            URLQueryItem(name: "vcSchemaId", value: schemaId)
        ]
        guard let url = components?.url else {
            throw IssueVcError.invalidWebFormURL
        }
        return url
    }

    // Convert plan.issuanceMode to a routing mode. nil / .DIRECT → TAS, .PROXY → first entry of endpoints.
    private static func issuanceMode(of plan: VCPlan) throws -> IssuanceMode {
        guard plan.issuanceMode == .PROXY else {
            return .tas
        }
        guard let endpoint = plan.endpoints?.first else {
            throw IssueVcError.missingProxyEndpoint
        }
        return .proxy(urlString: endpoint)
    }
}
