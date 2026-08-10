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
    case missingProfile
    case missingVcId
}

// MARK: - VC 발급 흐름 (OpenDID SDK 사용 예시)
//
// 진입점은 두 단계로 나뉜다:
//
//   preProcess(vcPlanId:issuer:offerId:)   ─ 사용자 인증 전
//     [1] propose-issue-vc          TAS 에 발급 의사 전달 → txId/refId
//     [2] (parallel) request-wallet-token
//     [3] ECDH                      .tas 모드에서만 — sharedSecret 도출
//     [4] request-server-token      .tas 모드에서만 — hServerToken
//     [5] request-issue-profile     발급자 프로필 + authNonce 수령
//
//   process(passcode:)                     ─ 사용자 PIN/BIO 인증 직후
//     [6] getSignedDidAuth          authNonce 를 holder DID 키로 서명 (sync)
//     [7] request-issue-vc          서명된 didAuth + 토큰으로 VC 요청 → vcId
//     [8] confirm-issue-vc          발급 완료 확정
//
// 편의를 위해 두 단계를 연속 호출하는 정적 진입점도 제공:
//   IssueVcProtocol.issue(plan:passcode:)
//   IssueVcProtocol.issue(offer:passcode:)
//
// 패턴 출처: did-ca-ios (UIKit reference) — 단일 HTTP 호출 = 단일 private
// 메서드, 인스턴스 상태(txId/hServerToken/issueProfile/vcId)는 단계 사이로
// 전달되어 orchestration 함수(preProcess/process) 본문이 스크립트처럼 읽힘.
nonisolated final class IssueVcProtocol {

    // MARK: - 라우팅 모드 (.tas / .proxy)
    private let mode: IssuanceMode

    // MARK: - 단계별 누적 상태
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

    // MARK: - [3] ECDH — holder DID 기반 sharedSecret 도출 (.tas 전용)
    private func deriveSharedSecret() async throws {
        self.sharedSecret = try await TokenGenerator.getSharedSecret(type: .holder, txId: txId)
    }

    // MARK: - [4] request-server-token (.tas 전용, sharedSecret 필요)
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
        // .tas 는 ECDH 로 받은 serverToken 으로 식별하지만, .proxy 는 serverToken 핸드셰이크가
        // 없으므로 serverToken 대신 userId 로 사용자를 식별한다.
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
        // profile 응답의 최신 txId 로 갱신 — request-issue-vc 단계에서 사용.
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
        // requestIssueVc 응답의 최신 txId — propose 단계의 것과 다를 수 있음.
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

    // MARK: - 진입점: 사용자 인증 전 단계 (1 ~ 5)
    func preProcess(vcPlanId: String, issuer: String, offerId: String?) async throws {
        try await proposeIssueVc(vcPlanId: vcPlanId, issuer: issuer, offerId: offerId)

        // walletToken 은 sharedSecret/serverToken/profile 와 무관 — 백그라운드 동시 진행.
        async let walletTokenTask: () = requestWalletToken()

        // serverToken(ECDH 기반)은 TAS 직접 발급에서만 필요. proxy 는 발급자가 자체 처리.
        if case .tas = mode {
            try await deriveSharedSecret()
            try await requestServerToken()
        }

        try await requestIssueProfile()
        try await walletTokenTask
    }

    // MARK: - 진입점: 사용자 인증 후 단계 (6 ~ 8) + 후처리
    @discardableResult
    func process(passcode: String?) async throws -> String {
        try await requestIssueVc(passcode: passcode)
        try await confirmIssueVc()

        // proxy 로 발급했다면 발급자 endpoint 를 vcId 키로 보관 — 폐기 시 vcId 로 호스트 조회.
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
// preProcess + process 를 연속 호출하는 단일 진입점. 현재 UX 는 사용자 인증을
// SDK 핸드셰이크 *전에* 받기 때문에 두 단계를 분리할 필요가 없어 이 정적
// 메서드로 단일 호출이 가능. 두 단계 사이에 발급자 프로필 확인 같은 UI 가
// 들어가야 하면 instance API(preProcess → process) 를 직접 호출.
extension IssueVcProtocol {

    // 수동 발급 — plan.allowedIssuers / issuanceMode / endpoints 로 라우팅 결정.
    @discardableResult
    static func issue(plan: VCPlan, passcode: String?) async throws -> String {
        let proto = try await begin(plan: plan)
        return try await proto.process(passcode: passcode)
    }

    // preProcess(propose-issue-vc 등)까지만 수행한 인스턴스를 반환 — did-ca 순서처럼
    // preProcess 와 process 사이에 웹폼/인증 등 UI 를 끼워야 할 때 사용한다.
    // propose 가 먼저 실행되어 발급 트랜잭션(txId)이 생성된 뒤 addVcInfo 가 그 위에 얹힌다.
    static func begin(plan: VCPlan) async throws -> IssueVcProtocol {
        guard let issuer = plan.allowedIssuers?.first else {
            throw IssueVcError.noAllowedIssuer
        }
        let mode = try issuanceMode(of: plan)
        let proto = IssueVcProtocol(mode: mode)
        try await proto.preProcess(vcPlanId: plan.vcPlanId, issuer: issuer, offerId: nil)
        return proto
    }

    // QR 발급 — offer 의 vcPlanId/issuer/offerId 만으로 TAS 직행. plan list
    // 조회 없음 (did-ca-ios 패턴): SDK 응답에 issuanceMode 가 없어 client 분기
    // 불가. PROXY 모드 plan 발급은 수동 Add VC 경로(issue(plan:)) 전용.
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

    // 발급 추가정보 입력 웹 폼 URL — DEMO_URL/addVcInfo?did=&userName=&vcSchemaId=.
    // holder DID id, userName(WalletState — OID4VCI user initiation 과 같은 값), plan 의 schema id 를
    // 쿼리로 싣는다. schema id 는 "...?id=<값>" 형태일 수 있어 '=' 뒤를 취한다.
    static func webFormURL(for plan: VCPlan) throws -> URL {
        let holderDid = try WalletAPI.shared.getDidDocument(type: .HolderDidDocumnet).id
        let userId = WalletState.userName ?? ""
        let schemaId = plan.credentialSchema.id.components(separatedBy: "=").last
            ?? plan.credentialSchema.id

        var components = URLComponents(string: URLs.DEMO_URL + "/addVcInfo")
        components?.queryItems = [
            URLQueryItem(name: "did", value: holderDid),
            URLQueryItem(name: "userName", value: userId),
            URLQueryItem(name: "vcSchemaId", value: schemaId)
        ]
        guard let url = components?.url else {
            throw IssueVcError.invalidWebFormURL
        }
        return url
    }

    // plan.issuanceMode 를 라우팅 모드로 변환. nil / .DIRECT → TAS, .PROXY → endpoints 첫 항목.
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
