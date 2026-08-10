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

enum VerifyVcError: Error {
    case noMatchingCredential
    case missingProfile
    /// 스키마·발급자 조건에는 맞는 VC 를 갖고 있는데, 프로파일이 그 VC 에 없는 claim 을
    /// `requiredClaims`/`displayClaims` 로 요구함 — 검증자 설정 오류.
    /// (보유 VC 자체가 없는 건 `noMatchingCredential` 로 구분한다.)
    case profileClaimMismatch
}

// `AppError.other` 는 `"\(error)"` 로 문구를 만든다 — enum case 이름이 그대로 노출되지 않도록
// 사용자에게 보일 문장을 여기서 준다.
extension VerifyVcError: CustomStringConvertible {
    var description: String {
        switch self {
        case .noMatchingCredential:
            return "You don't have a credential that matches this request."
        case .missingProfile:
            return "The presentation request is no longer available. Please scan again."
        case .profileClaimMismatch:
            return "The verifier's request is invalid. Please contact the requesting institution."
        }
    }
}

// MARK: - 일반 VP 제출 흐름 (OpenDID SDK 사용 예시)
//
// 진입점은 두 단계로 나뉜다:
//
//   preProcess(offerId:)                   ─ 사용자 인증 전
//     [1] request-profile          verifier 프로필 조회 → 검증자 정보 / 요구 스키마 / txId
//     [2] request-wallet-token     LIST_VC_AND_PRESENT_VP 용도
//
//   process(claimInfos:passcode:)          ─ 사용자 PIN/BIO 인증 직후
//     [3] createEncVp + request-verify
//                                   wallet 의 VC 로 암호화 VP 를 만들고 verifier 에 제출
//
// 편의를 위해 정적 진입점도 제공:
//   VerifyVcProtocol.requestProfile(offerId:)   ─ preProcess 만 실행 후 profile 반환
//   VerifyVcProtocol.presentationSummary(profile:)  ─ 화면·제출 공용 산출(규칙 적용 지점)
//   VerifyVcProtocol.submit(profile:summary:…)      ─ 그 산출 + 사용자 체크 → process 연쇄
//
// 패턴 출처: did-ca-ios 의 `VerifyVcProtocol` (CommonProtocol 기반 singleton).
// DIDCA 는 throwaway instance + static convenience 조합으로 호출자 API 를
// 종전과 동일하게 유지.
nonisolated final class VerifyVcProtocol {

    // MARK: - 단계별 누적 상태
    private var verifyProfile: _RequestProfile? = nil
    private var hWalletToken: String = ""
    private var txId: String = ""

    init() {}

    // MARK: - [1] request-profile
    @discardableResult
    private func requestProfile(offerId: String) async throws -> _RequestProfile {
        let request = RequestProfile(id: UUID().uuidString, offerId: offerId)
        let urlString = URLs.VERIFIER_URL + "/verifier/api/v1/request-profile"
        let response: _RequestProfile = try await HttpClient.sendPostRequest(
            urlString: urlString,
            request: request
        )
        self.verifyProfile = response
        self.txId = response.txId
        return response
    }

    // MARK: - [2] request-wallet-token
    private func requestWalletToken() async throws {
        self.hWalletToken = try await TokenGenerator.requestWalletToken(
            purpose: .LIST_VC_AND_PRESENT_VP
        )
    }

    // MARK: - [3] createEncVp + request-verify
    private func requestVerify(claimInfos: [ClaimInfo], passcode: String?) async throws {
        guard let profile = verifyProfile else {
            throw VerifyVcError.missingProfile
        }
        let (accE2e, encVp) = try await WalletAPI.shared.createEncVp(
            hWalletToken: hWalletToken,
            claimInfos: claimInfos,
            verifierProfile: profile,
            APIGatewayURL: URLs.API_URL,
            passcode: passcode
        )
        let request = RequestVerify(
            id: UUID().uuidString,
            txId: txId,
            accE2e: accE2e,
            encVp: MultibaseUtils.encode(type: .base58BTC, data: encVp)
        )
        let urlString = URLs.VERIFIER_URL + "/verifier/api/v1/request-verify"
        try await HttpClient.sendPostRequest(urlString: urlString, request: request)
    }

    // MARK: - 진입점: 사용자 인증 전 단계 (1 ~ 2)
    @discardableResult
    func preProcess(offerId: String) async throws -> _RequestProfile {
        try await requestProfile(offerId: offerId)
        try await requestWalletToken()
        // requestProfile 직후 verifyProfile 가 채워지므로 안전.
        return verifyProfile!
    }

    // MARK: - 진입점: 사용자 인증 후 단계 (3)
    func process(claimInfos: [ClaimInfo], passcode: String?) async throws {
        try await requestVerify(claimInfos: claimInfos, passcode: passcode)
    }
}

// MARK: - Static convenience
//
// 현재 UX 는 (1) QR 스캔 → profile 조회 후 VP 요청 화면 표시, (2) 사용자가
// 제출 버튼 → 인증 → 제출, 의 두 분기 사용자 액션이라 protocol 인스턴스를
// 두 단계 사이에서 유지하지 않음. 각 static 메서드가 throwaway 인스턴스를
// 생성하므로 walletToken 은 submit 단계에서 재발급 (cost 무시 수준).
extension VerifyVcProtocol {

    /// VP 제출 1단계 — verifier 프로필 조회.
    /// 내부적으로 preProcess(request-profile + request-wallet-token) 수행 후 profile 만 반환.
    static func requestProfile(offerId: String) async throws -> _RequestProfile {
        let proto = VerifyVcProtocol()
        return try await proto.preProcess(offerId: offerId)
    }

    /// VP 제출 2단계 — 표시 단계에서 확정한 제출 계획에 사용자 체크를 얹어 암호화 VP 를 제출.
    /// passcode 는 PIN 인증이면 입력값, BIO 면 nil.
    ///
    /// VC 선택·노출·필수 판정은 전부 `presentationSummary` 에서 끝났고 여기서 다시 하지 않는다 —
    /// 같은 규칙을 두 벌로 두면 화면에 보여 준 것과 실제로 나가는 것이 어긋난다.
    /// - parameter summary: `presentationSummary` 가 만든 것 그대로.
    /// - parameter selectedCodes: credentialId → 사용자가 체크한 code. 화면에 뜬 문서는 전부 담긴다
    ///   (체크가 하나도 없으면 빈 집합).
    static func submit(profile: _RequestProfile,
                       summary: VpPresentationSummary,
                       passcode: String?,
                       selectedCodes: [String: Set<String>] = [:]) async throws {
        // 제출 = requiredCodes ∪ 체크. 코드 순서는 의미가 없다 — SDK `VCManager.makePresentation` 이
        // VC 의 claim 순서를 돌며 이 목록을 포함 여부로만 쓴다.
        let claimInfos: [ClaimInfo] = summary.documents.compactMap { doc in
            let checked = selectedCodes[doc.credentialId] ?? []
            // 체크가 하나도 안 남은 카드는 제출에서 뺀다. 숨은 required 만 내보내면
            // 사용자가 "이 카드는 안 내겠다"고 표시한 것이 그대로 나가 버린다.
            guard !checked.isEmpty else { return nil }
            return ClaimInfo(credentialId: doc.credentialId,
                             claimCodes: Array(doc.requiredCodes.union(checked)))
        }
        guard !claimInfos.isEmpty else { throw VerifyVcError.noMatchingCredential }

        let proto = VerifyVcProtocol()
        // preProcess 결과(profile)는 호출자가 이미 갖고 있으므로 [1] 은 건너뛰고
        // 상태만 인스턴스에 주입. walletToken 만 새로 발급([2] 재실행).
        proto.verifyProfile = profile
        proto.txId = profile.txId
        try await proto.requestWalletToken()

        try await proto.process(claimInfos: claimInfos, passcode: passcode)
    }

}

// 표시 모델(`VpPresentationSummary` 등)은 `Logic/Display/PresentationSummary.swift` 에 있다 —
// OID4VP 도 같은 타입을 만들어 같은 화면에 넘기므로 특정 프로토콜에 두지 않는다.

extension VerifyVcProtocol {

    /// 프로파일 + 지갑 VC → 화면·제출 공용 산출. **제출 프로파일 규칙을 적용하는 유일한 지점**이다.
    /// 스키마 하나가 카드 하나이며, 순서는 이렇다.
    ///
    /// 1. 후보 = `credentialSchema.id` 일치 && (`allowedIssuers` 없거나 발급자 포함)
    /// 2. 어느 스키마에도 후보가 없으면 `noMatchingCredential` — 프로파일은 멀쩡하고 카드가 없는 것
    /// 3. `presentAll = true` → `displayClaims`·`requiredClaims` 를 읽지 않는다.
    ///    노출 = VC claim 전체, 전부 잠금 + 전부 제출
    /// 4. `presentAll ≠ true` → 후보 중 `requiredClaims ∪ displayClaims` 를 **전부 보유한** 첫 VC 선택.
    ///    그런 VC 가 없으면 `profileClaimMismatch` — 카드는 있는데 프로파일이 없는 claim 을 요구한 것
    /// 5. 노출 = `displayClaims`(nil·빈 배열이면 VC claim 전체), VC claim 순서 유지
    /// 6. 잠금 = 노출 ∩ `requiredClaims`. 나머지 노출분은 해제 가능
    /// 7. 제출은 `submit` 에서 `requiredCodes ∪ 체크` — required 는 노출 밖에 숨을 수 있어 따로 싣는다
    static func presentationSummary(profile: _RequestProfile) async throws -> VpPresentationSummary {
        let verifierName = profile.profile.profile.verifier.name
        let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .LIST_VC_AND_PRESENT_VP)
        let vcs = (try WalletAPI.shared.getAllCredentials(hWalletToken: hWalletToken)) ?? []

        var documents: [VpPresentationDocument] = []
        for schema in profile.profile.profile.filter.credentialSchemas {
            // [1] 후보 추리기. 후보가 없는 스키마는 건너뛴다 — 하나도 없으면 [2] 에서 일괄 처리.
            let candidates = vcs.filter { vc in
                vc.credentialSchema.id == schema.id
                    && (schema.allowedIssuers?.contains(vc.issuer.id) ?? true)
            }
            guard !candidates.isEmpty else { continue }

            let vc: VerifiableCredential
            let shownCodes: [String]
            let requiredCodes: Set<String>

            if schema.presentAll ?? false {
                // [3] 전체 공개. claim 목록을 읽지 않으므로 프로파일 불일치가 성립하지 않는다.
                vc = candidates[0]
                shownCodes = vc.credentialSubject.claims.map(\.code)
                requiredCodes = Set(shownCodes)
            } else {
                let required = Set(schema.requiredClaims ?? [])
                // 빈 배열은 "지정 없음"과 같게 본다 → 전체 노출.
                let display: Set<String>? = schema.displayClaims.flatMap { $0.isEmpty ? nil : Set($0) }
                // [4] 프로파일이 지목한 claim 을 전부 가진 후보를 고른다.
                let needed = required.union(display ?? [])
                guard let matched = candidates.first(where: { candidate in
                    needed.isSubset(of: Set(candidate.credentialSubject.claims.map(\.code)))
                }) else {
                    throw VerifyVcError.profileClaimMismatch
                }
                vc = matched
                // [5] 노출 = displayClaims, VC claim 순서 유지. 미지정이면 전체.
                let allCodes = vc.credentialSubject.claims.map(\.code)
                shownCodes = display.map { display in allCodes.filter(display.contains) } ?? allCodes
                requiredCodes = required
            }

            let claimsByCode = Dictionary(vc.credentialSubject.claims.map { ($0.code, $0) },
                                          uniquingKeysWith: { first, _ in first })
            // [6] 잠금 = 노출 ∩ required. 화면 밖 required 는 여기 안 나타나고 requiredCodes 로만 실린다.
            let claims: [VpPresentationClaim] = shownCodes.compactMap { code in
                guard let claim = claimsByCode[code] else { return nil }
                return VpPresentationClaim(
                    code: code,
                    label: claim.caption,
                    value: claim.value,
                    locked: requiredCodes.contains(code)
                )
            }
            let title = (try? await CredentialStore.shared.schema(id: schema.id))?.title ?? "Credential"
            documents.append(VpPresentationDocument(
                credentialId: vc.id, title: title, claims: claims,
                requiredCodes: requiredCodes,
                bindingKeyId: nil))   // 일반 VP 는 W3C 전용 — 서명키는 passcode 유무로 갈린다.
        }
        // [2] 어느 스키마에도 후보가 없었음.
        guard !documents.isEmpty else { throw VerifyVcError.noMatchingCredential }
        return VpPresentationSummary(verifierName: verifierName, documents: documents)
    }
}
