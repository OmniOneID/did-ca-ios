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

// MARK: - VC 폐기 흐름 (OpenDID SDK 사용 예시)
//
// 진입점은 두 단계로 나뉜다:
//
//   preProcess(vcId:)                      ─ 사용자 인증 전
//     [1] propose-revoke-vc        TAS/issuer 에 폐기 의사 전달 → txId/issuerNonce/authType
//     [2] ECDH                     TAS 직접 경로에서만 — sharedSecret 도출
//     [3] request-server-token     TAS 직접 경로에서만 — hServerToken
//
//   process(passcode:)                     ─ 사용자 PIN/BIO 인증 직후
//     [4] request-revoke-vc        지갑 키로 인증된 폐기 요청
//     [5] confirm-revoke-vc        폐기 완료 확정
//
// 정적 진입점 RevokeVcProtocol.revoke(vcId:passcode:) 는 walletToken 발급 →
// 서버 상태(.REVOKED) 단축 분기 → preProcess + process → 지갑 삭제까지 한
// 호출로 묶는다.
//
// 라우팅:
//   - proxy 발급분(`Preference.getIssuerEndpoint(forVcId:)` 존재) → issuer 직행,
//     ECDH/serverToken 단계 생략
//   - 그 외 → TAS(`.tas`) 경유, ECDH/serverToken 수행
//
// 페어 ZKP 가 있으면 `WalletAPI.deleteCredentials` 가 함께 삭제하므로 VC
// 폐기 호출만으로 충분.
//
// 패턴 출처: did-ca-ios `RevokeVcProtocol` (CommonProtocol singleton).
nonisolated final class RevokeVcProtocol {

    // MARK: - 라우팅 (호출자가 지정)
    private let host: String
    private let isTas: Bool
    private let hWalletToken: String

    // MARK: - 단계별 누적 상태
    private var vcId: String = ""
    private var hServerToken: String? = nil
    private var sharedSecret: Data? = nil
    private var txId: String = ""
    private var issuerNonce: String = ""
    // OptionSet — propose 응답이 채울 때까지 빈 set 으로 둠.
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

    // MARK: - [2] ECDH — holder DID 기반 sharedSecret 도출 (TAS 전용)
    private func deriveSharedSecret() async throws {
        self.sharedSecret = try await TokenGenerator.getSharedSecret(type: .holder, txId: txId)
    }

    // MARK: - [3] request-server-token (TAS 전용, sharedSecret 필요)
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
        // request-revoke-vc 응답의 최신 txId — confirm 단계에서 사용.
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

    // MARK: - 진입점: 사용자 인증 전 단계 (1 ~ 3)
    func preProcess(vcId: String) async throws {
        try await proposeRevokeVc(vcId: vcId)
        if isTas {
            try await deriveSharedSecret()
            try await requestServerToken()
        }
    }

    // MARK: - 진입점: 사용자 인증 후 단계 (4 ~ 5)
    func process(passcode: String?) async throws {
        try await requestRevokeVc(passcode: passcode)
        try await confirmRevokeVc()
    }
}

// MARK: - Static convenience
extension RevokeVcProtocol {

    /// VC 폐기 — walletToken 발급 → .REVOKED 단축 분기 → preProcess + process → 지갑 삭제까지 한 호출로 묶는다.
    /// passcode 는 PIN 인증이면 입력값, BIO 면 nil (SDK 가 bio 키 사용 시 시스템이 prompt).
    static func revoke(vcId: String, passcode: String?) async throws {
        let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .REMOVE_VC)

        // 폐기 여부는 현재 서버 상태가 중요하므로 캐시 무시하고 새로 조회한다.
        // 이미 폐기(.REVOKED)된 VC → 서버 프로토콜 건너뛰고 지갑에서 바로 삭제.
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

    /// 지갑에서 VC 실삭제 (페어 ZKP 도 함께 삭제됨) + 발급자 endpoint 매핑 정리.
    private static func deleteFromWallet(vcId: String, hWalletToken: String) throws {
        _ = try WalletAPI.shared.deleteCredentials(hWalletToken: hWalletToken, ids: [vcId])
        Preference.removeIssuerEndpoint(forVcId: vcId)
    }

    /// 폐기 라우팅 — proxy 발급분이면 발급 시 보관한 endpoint, 아니면 TAS.
    /// `isTas` 는 serverToken(ECDH) 단계 수행 여부를 결정한다.
    private static func revokeRoute(forVcId vcId: String) -> (host: String, isTas: Bool) {
        if let endpoint = Preference.getIssuerEndpoint(forVcId: vcId), !endpoint.isEmpty {
            return (endpoint, false)
        }
        return (TASConnection.routeHost(mode: .tas), true)
    }
}
