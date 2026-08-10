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

enum OID4VPPresenterError: Error {
    /// 요청에 제출할 수 있는 크리덴셜이 없음 — 표시 단계에서는 매칭된 credentialId 의 실물을
    /// 저장소에서 못 찾아 카드가 하나도 안 나온 경우, 제출 단계에서는 지갑이 비었거나 동의 반영
    /// 후 남는 크리덴셜이 없는 경우다.
    /// 뒤엣것은 DCQL 경로에서 UI 로 도달할 수 없다 — 잠금이 항상 1개 이상이라 카드를 비울 수
    /// 없기 때문이다(아래 "공개 범위" 참조). 거짓 성공을 막는 안전망으로만 남긴다.
    case noEligibleCredentials
    /// QR 페이로드에 `request_uri` 쿼리가 없거나 URL 로 파싱되지 않음.
    case invalidRequestURI
    /// `request_uri` GET 이 200 이 아님 (인가요청 JWS 를 못 받음).
    case failedToFetchJWS
    /// `request_uri` 응답 본문이 UTF-8 문자열이 아님 (compact JWS 가 아예 아님).
    /// 3-파트 위반·base64url 오류·헤더 JWK 누락은 SDK `JWS` 가 자체 오류로 던진다.
    case malformedJWS
    /// 인가요청 JWS 서명 검증 실패.
    case failedToVerifyJWS
    /// vp_token 제출이 비-2xx 응답. HTTP 상태 코드를 함께 전달.
    case failedToSubmit(Int)
}

// MARK: - OID4VP 제출 흐름 (SDK `WalletAPI` + 이식한 `OID4VPProtocol` API)
//
// 일반 VP(`VerifyVcProtocol`) 와 평행 구조다. 차이는 (1) 페이로드 진입이 verifier
// request-profile 대신 `openid4vp://...?request_uri=` 인가요청 이고, (2) 매칭이
// 제출 프로파일 스키마 대신 DCQL 쿼리(`WalletAPI.matchCredentials`) 이고, (3) 제출이
// request-verify 대신 authorization response(vp_token) 라는 점.
//
// 제출은 포맷과 무관하게 SDK 한 경로다 — 어느 저장소를 읽을지는 요청의 `format` 이 정하고(SDK),
// createVpToken 이 포맷별 presenter 로 vp_token 을 조립하며(SD-JWT=KB-JWT 문자열, W3C=ldp_vp 객체),
// 전송 가능한 form body(평문 / direct_post.jwt 면 JWE 봉인)까지 만들어 준다. submitVpToken 은 그
// body 를 `response_uri` 로 POST 하기만 한다. 앱은 포맷도, 저장소가 둘로 갈려 있다는 사실도 알지 않는다.
//
// 제출 집합 = verifier 요청(DCQL 매칭) ∩ 사용자 동의(선택분). 두 제약의 교집합이며 어느 쪽도
// 넘어서지 않는다 — 동의는 `VPRequestView` 가 선택분으로 확정해 넘긴다(해제분 아님).
//
// 단계 매핑 ([1]/[5] 후반은 SDK OID4VPProtocol 을 이식한 앱 구현, 나머지는 SDK 호출):
//   [1] getAuthorizationRequest(uri:)                  request_uri GET → JWS verify → AuthorizationRequest
//   [2] TokenGenerator.requestWalletToken              .LIST_VC_AND_PRESENT_VP 지갑 토큰
//   [3] WalletAPI.matchCredentials                     format → 저장소 선택 → DCQL 매칭
//                                                      → [MatchedCredential] (DCQL 선언 순서)
//   [4] (앱 UI) 사용자 동의 + PIN/BIO 인증 → applyConsent 로 매칭 결과를 좁힘
//   [5] WalletAPI.createVpToken → submitVpToken        SDK 가 조립·서명·봉인, 앱은 POST 만 (양 포맷 공통)
//
// 표시(presentationSummary)와 제출(submit)은 같은 근거로 매칭한다 — 둘 다 SDK 단일 진입점
// `matchCredentials(hWalletToken:authRequest:)` 하나로 제출 대상을 정한다. 크리덴셜 실물은
// 매칭에 쓰지 않고 오직 카드에 값을 그리는 렌더링에만 쓴다(MatchedCredential 은 값을 담지 않으므로).
// 따라서 화면에 뜬 카드 = 제출 대상이 항상 일치하며, 매칭 실패는 카드 누락이 아니라 표시 실패로 전파된다.
//
// 공개 범위 — 두 포맷이 같은 규칙을 쓴다:
//  - 노출은 항상 **크리덴셜 전체** (W3C=claim 전체 / SD-JWT=보유 disclosure 전체).
//    DCQL 에는 OpenDID 제출 프로파일의 `displayClaims` 같은 "보여줄 것" 축이 없기 때문이다.
//  - 잠금(필수)은 SDK 가 돌려준 `MatchedCredential.claimCodes` 그대로다. verifier 가 `claims` 를
//    지정하지 않아도 SDK 가 전 claim 을 채워 주므로(협의된 계약), 앱이 DCQL 을 들여다볼 일이 없다.
//    쿼리 미지정 = 전 항목 잠금 = 전체 강제 공개가 된다.
//  - 잠금은 해제할 수 없고 진입 시부터 체크 상태다. `claimCodes` 가 비어 오지 않는다는 계약과
//    합쳐지면 **카드는 UI 로 비울 수 없다** — 잠금이 항상 1개 이상이기 때문이다.
//  - 제출은 쿼리별로 `claimCodes ∪ 체크` 다. 위 이유로 이 합집합은 실제로는 체크 집합과 같지만,
//    화면이 그리지 못한 필수 code 가 있어도 빠지지 않도록 합집합으로 둔다(SD-JWT 이름공간 참고).
nonisolated enum OID4VPPresenter {

    /// VP 요청 화면 표시용 데이터 — 지갑 토큰 발급 → **submit 과 동일한 SDK 진입점으로 매칭** →
    /// 매칭된 credentialId 의 실물을 저장소에서 읽어 카드에 값을 그린다.
    ///
    /// 매칭 근거는 `WalletAPI.matchCredentials(hWalletToken:authRequest:)` 하나다(submit 과 동일).
    /// 매칭되는 VC 가 하나도 없으면 SDK 가 `noMatchedCredentials`(05502) 를 던지며(제시 불가),
    /// 이 throw 를 삼키지 않으므로 화면에 뜬 카드 = 제출 대상이 항상 일치한다(동의 무결성).
    /// 크리덴셜 실물 조회는 매칭이 아니라 값 렌더링 전용이다 — MatchedCredential 은 값을 담지 않는다.
    static func presentationSummary(authRequest: AuthorizationRequest) async throws -> VpPresentationSummary {
        // 매칭·렌더링이 같은 토큰을 쓴다 — .LIST_VC_AND_PRESENT_VP 는 저장소 조회 권한도 포함한다.
        let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .LIST_VC_AND_PRESENT_VP)

        // [정본] 제출 대상 매칭 — submit 과 동일 진입점. 요청 format 을 보고 SDK 가 저장소를 골라
        // 매칭하며(요청은 단일 포맷; mixed/missing 이면 throw), 빈 매칭이면 noMatchedCredentials.
        let matched = try WalletAPI.shared.matchCredentials(
            hWalletToken: hWalletToken,
            authRequest: authRequest
        )

        // 요청 포맷(단일) — SDK 진입점이 이미 mixed/missing 을 걸렀으므로 첫 format 하나로 판정한다.
        let format = (authRequest.dcqlQuery.credentials ?? []).compactMap { $0.format }.first ?? ""

        // 카드는 크리덴셜 단위 — 쿼리 단위가 아니다. 매칭을 크리덴셜로 합쳐 놓고 렌더링한다.
        let merged = mergeByCredential(matched)

        // 매칭 결과를 카드로 렌더링 — 요청 포맷에 해당하는 저장소 한쪽만 읽어 값을 채운다.
        let documents: [VpPresentationDocument]
        switch format {
        case VerifiableCredentialAdapter.format:   // "opendid_vc" (W3C VC)
            documents = try await w3cDocuments(merged: merged, hWalletToken: hWalletToken)
        case sdJwtFormat:                          // "dc+sd-jwt-did" (OID4VCI 발급분)
            documents = try sdjwtDocuments(merged: merged, hWalletToken: hWalletToken)
        default:
            documents = []
        }

        guard !documents.isEmpty else { throw OID4VPPresenterError.noEligibleCredentials }

        // OID4VP 에는 verifier 프로필이 없다 — client_metadata 의 표시명, 없으면 client_id.
        let verifierName = authRequest.clientMetadata["client_name"]?.asString ?? authRequest.clientId
        return VpPresentationSummary(verifierName: verifierName, documents: documents)
    }

    /// SD-JWT 포맷 토큰 — SDK `SDJWTCredentialAdapter.supportedFormats` 와 같은 값(그쪽은 private).
    private static let sdJwtFormat = "dc+sd-jwt-did"

    /// 매칭 결과를 크리덴셜 단위로 합친다 — 카드 하나 = 크리덴셜 한 장.
    ///
    /// 한 크리덴셜이 쿼리 여러 개에 걸릴 수 있는데, 노출이 쿼리와 무관하게 크리덴셜 전체이므로
    /// 쿼리별로 다른 건 필수 집합뿐이다. 합집합으로 합치면 잃는 정보가 없다 — 앞선 매칭만 남기고
    /// 뒤를 버리면 뒤 쿼리가 요구한 필수 claim 이 화면에서 통째로 사라진다.
    /// 순서는 SDK 가 준 순서(DCQL 선언 순 — 결정적)를 그대로 쓴다.
    private static func mergeByCredential(
        _ matched: [MatchedCredential]
    ) -> [(credentialId: String, requiredCodes: Set<String>)] {
        var orderedIds: [String] = []
        var requiredByCredential: [String: Set<String>] = [:]
        for mc in matched {
            if requiredByCredential[mc.credentialId] == nil {
                orderedIds.append(mc.credentialId)
                requiredByCredential[mc.credentialId] = []
            }
            requiredByCredential[mc.credentialId]?.formUnion(mc.claimCodes)
        }
        return orderedIds.map { ($0, requiredByCredential[$0] ?? []) }
    }

    /// W3C VC 카드 렌더링 — 매칭된 credentialId 의 실물을 `getAllCredentials` 에서 읽어 값을 채운다.
    /// 노출은 VC claim 전체, 잠금은 매칭이 지목한 code 다.
    private static func w3cDocuments(
        merged: [(credentialId: String, requiredCodes: Set<String>)],
        hWalletToken: String
    ) async throws -> [VpPresentationDocument] {
        let credentials = (try WalletAPI.shared.getAllCredentials(hWalletToken: hWalletToken)) ?? []
        var documents: [VpPresentationDocument] = []
        for entry in merged {
            guard let vc = credentials.first(where: { $0.id == entry.credentialId }) else { continue }
            let claims = vc.credentialSubject.claims.map { claim in
                VpPresentationClaim(
                    code: claim.code,
                    label: claim.caption,
                    value: claim.value,
                    locked: entry.requiredCodes.contains(claim.code)
                )
            }
            let title = (try? await CredentialStore.shared.schema(id: vc.credentialSchema.id))?.title ?? "Credential"
            documents.append(VpPresentationDocument(
                credentialId: vc.id,
                title: title,
                claims: claims,
                requiredCodes: entry.requiredCodes,
                bindingKeyId: nil           // W3C 는 서명키가 고정이 아니라 passcode 유무로 갈린다.
            ))
        }
        return documents
    }

    /// SD-JWT 카드 렌더링 — 매칭된 credentialId 의 실물을 `getAllOID4VCs` 에서 읽어 disclosure 를 그린다.
    ///
    /// 노출은 **보유 disclosure 전체**다. 매칭이 지목한 것만 그리면 verifier 가 요구하지 않은 항목을
    /// 사용자가 자발적으로 낼 길이 없어지고, 화면이 요청 범위를 그대로 따라가 버린다.
    /// 잠금은 매칭이 지목한 code — 그 판정에 DCQL 을 다시 읽지 않는다.
    ///
    /// 평문 claim(`iss`/`exp`/`vct` 등 페이로드에 그대로 실린 값)은 감출 수단이 없고 화면에도 띄우지
    /// 않는다. 현재 발급물에서는 평문이 전부 SDK `reservedClaims` 라 사용자에게 보일 정보가 빠지지 않는다.
    private static func sdjwtDocuments(
        merged: [(credentialId: String, requiredCodes: Set<String>)],
        hWalletToken: String
    ) throws -> [VpPresentationDocument] {
        let issued = try WalletAPI.shared.getAllOID4VCs(hWalletToken: hWalletToken)
        var documents: [VpPresentationDocument] = []
        for entry in merged {
            guard let cred = issued.first(where: { $0.id == entry.credentialId }) else { continue }
            let claims = cred.sdjwt.disclosures.map { disclosure -> VpPresentationClaim in
                let code = disclosure.claimName ?? ""
                // 복합값(object/array)이면 하위 항목을 채워 접이식 그룹으로, 스칼라면 단일 행.
                // SD-JWT disclosure 는 원자 단위라 토글은 상위(disclosure) 기준 — 하위는 표시 전용.
                let children = Self.childClaims(of: disclosure.claimValue, parentCode: code)
                return VpPresentationClaim(
                    code: code,
                    label: code,
                    value: children.isEmpty ? SdJwtClaimDisplay.scalarString(disclosure.claimValue) : "",
                    locked: entry.requiredCodes.contains(code),
                    children: children
                )
            }
            documents.append(VpPresentationDocument(
                credentialId: cred.id,
                // 제목 규칙은 목록·상세와 공유 — SdJwtClaimDisplay 참조.
                title: SdJwtClaimDisplay.title(of: cred),
                claims: claims,
                requiredCodes: entry.requiredCodes,
                // 발급 시 바인딩된 키 — 제출 인증수단은 이 값이 정한다 (사용자 선택 불가).
                bindingKeyId: cred.kid
            ))
        }
        return documents
    }

    /// VP 생성 + 제출. 매칭·조립·전송 모두 SDK 한 경로다 — 앱은 포맷을 알지 않는다.
    ///
    /// **어떤 크리덴셜을 낼지는 요청이 정한다.** SDK 진입점이 `dcql_query.credentials[].format` 을
    /// 보고 해당 저장소(W3C=`getAllCredentials` / SD-JWT=`getAllOID4VCs`)를 읽는다. 앱이 두 저장소를
    /// 모두 뒤져 하나를 고르던 방식은 지갑 보유분이 제출 대상을 정하게 만들어, 화면(요약)과 제출이
    /// 어긋날 수 있었다.
    /// 제출 대상이 하나도 없으면 `OID4VPPresenterError.noEligibleCredentials` 로 중단(거짓 성공 방지).
    /// passcode 는 PIN 인증이면 입력값, BIO 면 nil(SDK 가 서명 시점에 생체 트리거).
    ///
    /// ⚠️ 한계: 한 요청이 두 포맷을 함께 요구하면 SDK 매칭 진입점이 거부한다
    /// (`unsupportedPresentationFormat`). 전송 계층은 혼합을 담을 수 있으나 매칭이 `credential_sets`
    /// 충족 판정을 호출 단위로 하기 때문이며, 해소는 SDK 몫이다. 요청에 `format` 이 없어도 같은
    /// 예외가 난다 — 규격상 필수이므로 앱이 추측해 폴백하지 않는다.
    /// - parameter selectedCodes: credentialId → 사용자가 공개에 동의한 claim(disclosure) 이름.
    ///   제출 집합은 `verifier 요청(매칭 결과) ∩ 사용자 동의` 다 — 포맷을 가리지 않으므로
    ///   W3C 에 DCQL claim 쿼리가 추가돼도 이 경로는 그대로다(잠금 여부는 표시 매퍼가 정한다).
    static func submit(authRequest: AuthorizationRequest,
                       passcode: String?,
                       selectedCodes: [String: Set<String>] = [:]) async throws {
        guard WalletAPI.shared.isAnyCredentialsSaved || WalletAPI.shared.isAnyOID4VCSaved else {
            throw OID4VPPresenterError.noEligibleCredentials
        }

        // 매칭·제출이 같은 토큰을 쓴다 — .LIST_VC_AND_PRESENT_VP 는 저장소 조회 권한도 포함한다.
        let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .LIST_VC_AND_PRESENT_VP)
        let matched = try WalletAPI.shared.matchCredentials(
            hWalletToken: hWalletToken,
            authRequest: authRequest
        )
        // 동의 반영 후 남는 게 없으면 거짓 성공 대신 중단 (현재 UI 로는 도달 불가한 안전망).
        let consented = Self.applyConsent(matched, selectedCodes: selectedCodes)
        guard !consented.isEmpty else {
            throw OID4VPPresenterError.noEligibleCredentials
        }

        // 서명키는 SDK 가 해결한다(SD-JWT=발급 시 바인딩된 kid, W3C=passcode 유무) — 앱은
        // hWalletToken/passcode 만 넘긴다. createVpToken 이 포맷별 presenter 로 vp_token 을 조립하고
        // (SD-JWT=KB-JWT 문자열, W3C=ldp_vp 객체 + client_id/nonce 바인딩), authorization response
        // form body 까지 만든다 — response_mode 가 direct_post.jwt 면 JWE 봉인도 여기서 끝난다.
        // submitVpToken 은 그 body 를 response_uri 로 POST 하기만 한다(비-2xx 면 failedToSubmit).
        let vpToken = try WalletAPI.shared.createVpToken(
            hWalletToken: hWalletToken,
            authRequest: authRequest,
            matchedCredentials: consented,
            passcode: passcode
        )
        try await Self.submitVpToken(authRequest: authRequest, vpToken: vpToken)
    }

    /// 사용자 체크를 매칭 결과에 반영한다 — **제출 = 쿼리별 필수 ∪ 체크**.
    ///
    /// 노출이 크리덴셜 전체이고 잠금은 해제할 수 없으므로 체크 집합은 이미 필수를 품고 있다. 그래도
    /// 합집합으로 두는 건, 화면이 그리지 못한 필수 code 가 있어도 제출에서 빠지지 않게 하기 위해서다
    /// (SD-JWT 는 표시 식별자와 SDK code 의 이름공간이 원리상 다르다 — 현재 발급물에선 같은 값이지만
    /// 발급 형태가 바뀌면 갈릴 수 있다). 필수는 verifier 가 요구한 것이므로 넘치는 공개도 아니다.
    ///
    /// - 체크가 하나라도 있음: `claimCodes ∪ 체크` — DCQL 경로는 항상 이 갈래로 온다.
    /// - 체크가 빈 집합: 그 크리덴셜을 드롭한다. **현재 UI 로는 도달할 수 없는 갈래다** — 잠금이
    ///   항상 1개 이상이라 카드를 통째로 비울 수 없기 때문이다. 그래도 남겨 두는 건, 빈 claimCodes 를
    ///   그대로 넘기면 SDK 가 "전체 공개"로 읽어 정반대 결과가 되기 때문이다(무동의 전체 공개 차단).
    ///   크리덴셜 단위 거부 UI 가 생기면 이 갈래가 정상 경로가 된다.
    /// - 맵에 키가 아예 없음: 화면에 없던 크리덴셜 — 매칭 결과를 그대로 둔다.
    ///   (화면에 뜬 문서는 체크가 없어도 빈 집합으로 담겨 오므로 이 갈래로 오지 않는다.)
    private static func applyConsent(
        _ matched: [MatchedCredential],
        selectedCodes: [String: Set<String>]
    ) -> [MatchedCredential] {
        matched.compactMap { mc in
            guard let checked = selectedCodes[mc.credentialId] else {
                return mc   // 화면에 없던 크리덴셜 — 매칭 결과 유지.
            }
            guard !checked.isEmpty else { return nil }   // 전부 해제 → 미제출
            return MatchedCredential(queryId: mc.queryId,
                                     credentialId: mc.credentialId,
                                     claimCodes: Array(checked.union(mc.claimCodes)))
        }
    }

    /// SD-JWT 복합값(object/array) → 접이식 그룹의 하위 VpPresentationClaim 목록. 스칼라면 빈 배열.
    /// 하위 code 는 `parent.field` / `parent[i]` 로 합성한다 — disclosure 는 원자 단위라 하위를 따로
    /// 공개·비공개할 수 없어 토글에는 쓰이지 않고 표시 전용이다. 그래서 locked(true) 로 둔다.
    /// 펼침 규칙은 `SdJwtClaimDisplay` 공유.
    private static func childClaims(of json: JSON, parentCode: String) -> [VpPresentationClaim] {
        SdJwtClaimDisplay.childRows(json).map {
            VpPresentationClaim(code: parentCode + $0.keySuffix, label: $0.label,
                                value: $0.value, locked: true)
        }
    }

}

// MARK: - 이식한 SDK OID4VPProtocol API (static · 이름/시그니처 그대로 · 상태 없음)
//
// OID4VCI(`IssueOID4VcProtocol`) 와 같은 이유·같은 방식의 이식이다. 두 API 모두 앱이 쥔 정보
// (인가요청 URI / 조립 끝난 form body)로 HTTP 를 한 번 치고 결과를 검증하는 얇은 계층이라
// SDK 표면에 묶어 둘 이유가 없다. 발급·서명·봉인 같은 본체는 그대로 SDK 몫이다.
//
// JWS 파싱·ES256 검증은 SDK `JWS` 정본을 그대로 쓴다(SD-JWT 처리와 같은 코드). 검증 키는 헤더에
// 실린 JWK 라 서명·페이로드 일치만 보증하며, verifier 신원 자체는 확인하지 않는다(SDK 문서 명시).
extension OID4VPPresenter {

    /// 인가요청 수신·파싱 — `request_uri` GET → JWS 서명 검증 → `AuthorizationRequest`.
    static func getAuthorizationRequest(uri: String) async throws -> AuthorizationRequest {
        guard
            let components = URLComponents(string: uri),
            let requestURI = components.queryItems?
                .first(where: { $0.name == "request_uri" })?
                .value
        else {
            throw OID4VPPresenterError.invalidRequestURI
        }

        let (encodedData, statusCode) = try await CommunicationClient.sendRequest(
            urlString: requestURI,
            httpMethod: .GET
        )

        guard statusCode == 200 else {
            throw OID4VPPresenterError.failedToFetchJWS
        }
        guard let compact = String(data: encodedData, encoding: .utf8) else {
            throw OID4VPPresenterError.malformedJWS
        }

        let jws = try JWS(from: compact)
        guard try jws.verify() else {
            throw OID4VPPresenterError.failedToVerifyJWS
        }

        // payload 는 snake_case — Jsonable 기본 디코더가 FromSnake 를 보고 변환해 준다.
        // (SDK `getPayload()` 는 internal 이라 payloadData 를 직접 디코딩한다.)
        return try AuthorizationRequest(from: jws.payloadData)
    }

    /// `createVpToken` 이 만들어 준 authorization response body 를 verifier 의 `response_uri` 로
    /// `application/x-www-form-urlencoded` POST 한다. body 조립·서명·JWE 봉인은 이미 끝난 상태다.
    /// - Returns: verifier 응답 본문과 HTTP 상태 코드.
    /// - Throws: 비-2xx 면 `OID4VPPresenterError.failedToSubmit`.
    @discardableResult
    static func submitVpToken(
        authRequest: AuthorizationRequest,
        vpToken: Data
    ) async throws -> (Data, Int) {
        let (data, statusCode) = try await CommunicationClient.sendPostUrlencoded(
            urlString: authRequest.responseUri,
            requestJsonData: vpToken
        )

        guard (200...299).contains(statusCode) else {
            throw OID4VPPresenterError.failedToSubmit(statusCode)
        }
        return (data, statusCode)
    }
}
