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
    static let host = URLs.TAS_URL
}

// MARK: - User Registration
extension TASConnection {

    /// 사용자 등록 트랜잭션 개시. 응답 txId 가 이후 단계의 상관관계 키로 사용됨.
    static func initiateUserRegistration() async throws -> String {
        let urlString = host + "/tas/api/v1/propose-register-user"
        let request = ProposeRegisterUser(id: UUID().uuidString)
        let response: _ProposeRegisterUser = try await HttpClient.sendPostRequest(
            urlString: urlString,
            request: request
        )
        return response.txId
    }

    /// PII 검증을 위한 KYC 조회 요청. kycTxId = signup 시 저장한 userId.
    static func retrieveKYC(request: RetrieveKyc) async throws {
        let urlString = host + "/tas/api/v1/retrieve-kyc"
        let _: _RetrieveKyc = try await HttpClient.sendPostRequest(
            urlString: urlString,
            request: request
        )
    }

    /// 사용자 등록 확정. requestRegisterUser 직후 호출.
    static func confirmUserRegistration(txId: String, serverToken: String) async throws {
        let urlString = host + "/tas/api/v1/confirm-register-user"
        let request = ConfirmRegisterUser(id: UUID().uuidString, txId: txId, serverToken: serverToken)
        let _: _ConfirmRegisterUser = try await HttpClient.sendPostRequest(
            urlString: urlString,
            request: request
        )
    }
}

// MARK: - DID Document Update (설정에서 BIO 추가/제거 시 holder 문서 갱신)
extension TASConnection {

    /// 문서 갱신 트랜잭션 개시. did = holder DID id. 응답 txId / authNonce 가 이후 단계 입력.
    static func proposeUpdateDidDoc(did: String) async throws -> _ProposeUpdateDidDoc {
        let urlString = host + "/tas/api/v1/propose-update-diddoc"
        let request = ProposeUpdateDidDoc(id: UUID().uuidString, did: did)
        return try await HttpClient.sendPostRequest(urlString: urlString, request: request)
    }

    /// 문서 갱신 확정. WalletAPI.shared.requestUpdateUser 직후 호출.
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

    /// 서버 토큰 생성용 암호화 컨테이너 요청 (encStd / iv).
    static func createToken(request: RequestCreateToken) async throws -> _RequestCreateToken {
        let urlString = host + "/tas/api/v1/request-create-token"
        return try await HttpClient.sendPostRequest(urlString: urlString, request: request)
    }

    /// ECDH 키 교환 (sharedSecret 도출용 서버 nonce·공개키 응답).
    static func requestEcdh(request: RequestEcdh) async throws -> _RequestEcdh {
        let urlString = host + "/tas/api/v1/request-ecdh"
        return try await HttpClient.sendPostRequest(urlString: urlString, request: request)
    }
}

// 발급 라우팅 모드. plan.issuanceMode 가 .DIRECT/없음 이면 TAS 직접, .PROXY 면 발급자 proxy 경유.
enum IssuanceMode {
    case tas
    case proxy(urlString: String)
}

// MARK: - VC Issuance
extension TASConnection {

    /// 발급 모드별 베이스 호스트. proxy 면 발급자 endpoint + "/proxy", 아니면 TAS.
    nonisolated static func routeHost(mode: IssuanceMode) -> String {
        switch mode {
        case .tas:                  return host + "/tas"
        case .proxy(let urlString): return urlString + "/proxy"
        }
    }

    /// 발급 가능한 VC plan 목록. 사용자가 "From list" 에서 고르는 메뉴 소스.
    /// primary / secondary 는 `tags[]=...` 쿼리로 부착되어 백엔드 측에서 plan 을 필터링하는 용도.
    /// 현재 DIDCA 는 필터링 없이 전체 목록을 받지만 시그니처는 CampusID 와 맞춰 두어 차후 활용.
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

    /// 발급 트랜잭션 개시. 응답 txId 가 이후 단계의 상관관계 키, refId 는 requestIssueVc 입력.
    static func proposeIssueVc(mode: IssuanceMode = .tas, request: ProposeIssueVc) async throws -> _ProposeIssueVc {
        let urlString = routeHost(mode: mode) + "/api/v1/propose-issue-vc"
        return try await HttpClient.sendPostRequest(urlString: urlString, request: request)
    }

    /// 발급자 프로필 + authNonce 조회. getSignedDidAuth 에 authNonce 가 들어감.
    static func requestIssueProfile(mode: IssuanceMode = .tas, request: RequestIssueProfile) async throws -> _RequestIssueProfile {
        let urlString = routeHost(mode: mode) + "/api/v1/request-issue-profile"
        return try await HttpClient.sendPostRequest(urlString: urlString, request: request)
    }

    /// 발급 확정. WalletAPI.shared.requestIssueVc 후 호출 — vcId 는 거기서 받은 값.
    static func confirmIssueVc(mode: IssuanceMode = .tas, request: ConfirmIssueVc) async throws -> _ConfirmIssueVc {
        let urlString = routeHost(mode: mode) + "/api/v1/confirm-issue-vc"
        return try await HttpClient.sendPostRequest(urlString: urlString, request: request)
    }
}

// MARK: - VC Revocation
extension TASConnection {

    /// 폐기 트랜잭션 개시. 응답 txId / issuerNonce / authType 가 이후 단계 입력.
    /// host 는 RevokeVcProtocol 이 결정한 베이스(proxy 발급자 endpoint 또는 TAS).
    static func proposeRevokeVc(host: String, request: ProposeRevokeVc) async throws -> _ProposeRevokeVc {
        let urlString = host + "/api/v1/propose-revoke-vc"
        return try await HttpClient.sendPostRequest(urlString: urlString, request: request)
    }
}
