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
// 공개 범위 — 세 포맷이 같은 규칙을 쓴다:
//  - 노출은 항상 **크리덴셜 전체** (W3C=claim 전체 / SD-JWT·mDoc=SDK consentItems 전체).
//    DCQL 에는 OpenDID 제출 프로파일의 `displayClaims` 같은 "보여줄 것" 축이 없기 때문이다.
//  - 잠금(필수)은 SDK 가 돌려준 `MatchedCredential.claimCodes` 그대로다. verifier 가 `claims` 를
//    지정하지 않아도 SDK 가 전 claim 을 채워 주므로(협의된 계약), 앱이 DCQL 을 들여다볼 일이 없다.
//    쿼리 미지정 = 전 항목 잠금 = 전체 강제 공개가 된다.
//  - 잠금은 해제할 수 없고 진입 시부터 체크 상태다. `claimCodes` 가 비어 오지 않는다는 계약과
//    합쳐지면 **카드는 UI 로 비울 수 없다** — 잠금이 항상 1개 이상이기 때문이다.
//  - 제출은 쿼리별로 `claimCodes ∪ 체크` 다. 합집합은 SDK 계약이기도 하다 — 선택은 매칭이 준
//    claimCodes 를 **좁힐 수 없고**(좁히면 SDK 가 invalidSelectedCredentials 로 거부한다), 넘어서는
//    code 는 그대로 통과해 그 claim 까지 공개된다. 화면에서 뺀 필수 code(평문 claim)도 이 합집합으로
//    제출에 남는다.
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
        //
        // "요청한 크리덴셜을 아예 보유하지 않음"은 오류가 아니라 **안내 대상**이다(PRES-E-04) —
        // ACTIVE 0건과 문구로 구분하지 않기로 했으므로 여기서 같은 것으로 바꿔 던진다.
        let matched: [MatchedCredential]
        do {
            matched = try WalletAPI.shared.matchCredentials(
                hWalletToken: hWalletToken,
                authRequest: authRequest
            )
        } catch let error as WalletCoreError where Self.meansNothingToSubmit(error) {
            throw NoSubmittableCredentialError()
        }

        // 카드는 크리덴셜 단위 — 쿼리 단위가 아니다. 매칭을 크리덴셜로 합쳐 놓고 렌더링한다.
        let merged = mergeByCredential(matched)

        // 매칭이 지목한 크리덴셜의 실물을 찾아 **타입으로** 렌더링 경로를 고른다.
        //
        // 요청의 `format` 문자열을 읽지 않는다. 포맷 토큰(`dc+sd-jwt-did` 등)을 앱이 들고 있으면
        // SDK 가 토큰을 바꿨을 때 분기가 조용히 default 로 떨어져 **오류 없이 빈 화면**이 된다.
        // 어느 저장소에서 나왔고 어떤 타입인지는 실물 자체가 말해 주므로 문자열이 필요 없다.
        // (매칭 진입점이 이미 요청 포맷으로 저장소를 골랐다 — 여기 온 실물은 그 결과다.)
        let documents = try await renderDocuments(merged: merged, hWalletToken: hWalletToken)

        // 매칭은 됐지만 ACTIVE 가 0건이거나 실물을 못 찾은 경우 — 미보유와 같은 안내로 묶는다.
        guard !documents.isEmpty else { throw NoSubmittableCredentialError() }

        // 카드가 남았어도 **쿼리 하나가 후보를 통째로 잃었으면** 그 요청은 채울 수 없다.
        try Self.requireEveryQuerySurvives(
            matched: matched,
            surviving: Set(documents.map(\.credentialId)),
            dcqlQuery: authRequest.dcqlQuery
        )

        // OID4VP 에는 verifier 프로필이 없다 — client_metadata 의 표시명, 없으면 client_id.
        let verifierName = authRequest.clientMetadata["client_name"]?.asString ?? authRequest.clientId
        return VpPresentationSummary(verifierName: verifierName, documents: documents)
    }

    /// 매칭 결과 → 카드. 두 저장소를 한 번씩 읽고, 크리덴셜마다 그 타입에 맞는 매퍼로 보낸다.
    /// 어느 저장소에도 없는 credentialId 는 건너뛴다.
    ///
    /// **ACTIVE 만 후보로 올린다**(PRES-B-06) — Inactive·Expired 는 단일/복수 판정과 옵션 목록에서
    /// 모두 빠진다. 판정 사다리는 `CredentialStore.submittableIds` 참조.
    /// 카드가 하나도 안 남으면 호출측이 PRES-E-04 로 안내한다.
    private static func renderDocuments(
        merged: [(credentialId: String, requiredCodes: Set<String>)],
        hWalletToken: String
    ) async throws -> [VpPresentationDocument] {
        // 비어 있는 저장소를 조회하지 않는다 — 요청은 단일 포맷이라 한쪽은 대개 비어 있다.
        let w3c = WalletAPI.shared.isAnyCredentialsSaved
            ? ((try WalletAPI.shared.getAllCredentials(hWalletToken: hWalletToken)) ?? [])
            : []
        let oid4vc = WalletAPI.shared.isAnyOID4VCSaved
            ? try WalletAPI.shared.getAllOID4VCs(hWalletToken: hWalletToken)
            : []

        // ACTIVE 판정을 카드 생성보다 **먼저, 한 번에** 한다 — 후보들이 대개 같은 Status List 를
        // 가리키므로 한 건씩 물으면 같은 토큰을 후보 수만큼 받고, 그중 일부만 실패하면 같은 리스트를
        // 근거로 하는 후보끼리 판정이 갈린다(`CredentialStore.submittableIds` 참조).
        let submittable = await CredentialStore.shared.submittableIds(
            among: merged.compactMap { entry in oid4vc.first { $0.id == entry.credentialId } }
        )

        var documents: [VpPresentationDocument] = []
        for entry in merged {
            switch oid4vc.first(where: { $0.id == entry.credentialId }) {
            case let cred as SdJwtCredentialItem:
                guard submittable.contains(cred.id) else { continue }
                documents.append(try sdjwtDocument(cred, requiredCodes: entry.requiredCodes))
            case let cred as MdocCredentialItem:
                guard submittable.contains(cred.id) else { continue }
                documents.append(mdocDocument(cred, requiredCodes: entry.requiredCodes))
            default:
                // W3C 는 조회처가 서버 `vc-meta` 라 VC 단위 API 다 — 묶을 수단이 없어 한 건씩 묻는다.
                guard let vc = w3c.first(where: { $0.id == entry.credentialId }) else { continue }
                guard await CredentialStore.shared.isSubmittable(w3c: vc) else { continue }
                documents.append(await w3cDocument(vc, requiredCodes: entry.requiredCodes))
            }
        }
        return documents
    }

    /// ACTIVE 필터가 **쿼리 하나의 후보를 전부** 걷어냈는지 본다 — 그랬다면 표시 단계에서 끝낸다.
    ///
    /// `renderDocuments` 는 Inactive·Expired 를 카드에서 빼지만(PRES-B-06), 제출 단계의 매칭은 그
    /// 필터를 모른다. 그래서 쿼리 A 는 활성 크리덴셜이 있고 쿼리 B 의 유일한 후보가 폐기된 경우
    /// 카드가 남아 동의 화면이 열리고, 사용자가 인증까지 끝낸 뒤 SDK 가 제출을 거부한다
    /// (`invalidSelectedCredentials` — 매칭된 쿼리 전부가 선택에 담겨야 한다). 채울 수 없는 요청은
    /// 실패 팝업이 아니라 **미보유와 같은 안내**(PRES-E-04)로 보내는 것이 맞고, 인증 전에 끝나야 한다.
    ///
    /// `credential_sets` 가 있으면 쿼리 하나가 비어도 다른 조합으로 요청이 채워질 수 있다. 그 충족
    /// 판정은 SDK 정본(`requireCredentialSetsSatisfied`)이 쥐고 있으므로 앱이 두 번째 구현을 두지
    /// 않는다 — 그 경우엔 판정을 포기하고 기존 동작(남은 카드 표시)을 유지한다.
    private static func requireEveryQuerySurvives(
        matched: [MatchedCredential],
        surviving: Set<String>,
        dcqlQuery: DCQLQuery
    ) throws {
        guard dcqlQuery.credentialSets?.isEmpty ?? true else { return }
        var survivedByQuery: [String: Bool] = [:]
        for mc in matched {
            survivedByQuery[mc.queryId, default: false] =
                survivedByQuery[mc.queryId, default: false] || surviving.contains(mc.credentialId)
        }
        guard survivedByQuery.values.allSatisfy({ $0 }) else {
            throw NoSubmittableCredentialError()
        }
    }

    /// SDK 매칭 실패 중 **"낼 것이 없다"** 로 읽어야 하는 것 — 오류 팝업이 아니라 PRES-E-04 안내다.
    ///   · 05502 `noMatchedCredentials`      — 요청에 맞는 크리덴셜을 보유하지 않음
    ///   · 05503 `credentialSetsNotSatisfied` — 보유분으로 요청한 조합을 채우지 못함
    /// 나머지 매칭 오류(포맷 미지원·DCQL 형식 오류 등)는 진짜 오류이므로 그대로 전파한다.
    private static func meansNothingToSubmit(_ error: WalletCoreError) -> Bool {
        error.code == "MSDKWLT05502" || error.code == "MSDKWLT05503"
    }

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

    /// W3C VC 카드 한 장 — 노출은 VC claim 전체, REQUIRED 는 매칭이 지목한 code 다.
    private static func w3cDocument(
        _ vc: VerifiableCredential,
        requiredCodes: Set<String>
    ) async -> VpPresentationDocument {
        let claims = vc.credentialSubject.claims.map { claim in
            VpPresentationClaim(
                code: claim.code,
                label: claim.caption,
                // 이미지 클레임(portrait 등)은 값 텍스트 대신 이미지로 그린다 — PRES-B-04.
                value: ImageClaim.claimValue(type: claim.type, encoded: claim.value),
                required: requiredCodes.contains(claim.code)
            )
        }
        let title = (try? await CredentialStore.shared.schema(id: vc.credentialSchema.id))?.title ?? "Credential"
        return VpPresentationDocument(
            credentialId: vc.id,
            title: title,
            claims: claims,
            requiredCodes: requiredCodes,
            bindingKeyId: nil           // W3C 는 서명키가 고정이 아니라 passcode 유무로 갈린다.
        )
    }

    /// SD-JWT 카드 한 장.
    ///
    /// 행의 근거는 SDK `consentItems` 다. **claim code 를 앱이 만들지 않는다** — code 를 만드는 쪽과
    /// 제출에서 해석하는 쪽이 SDK 안에서 하나로 묶여 있어, 앱이 disclosure 를 직접 걸어 이름을
    /// 합성하면 같은 규칙의 두 번째 구현이 되고 어긋나는 지점이 곧 제출 실패가 된다. 중첩·평문 여부와
    /// 한 code 가 두 claim 을 가리키는지도 그 걷기가 정한다(SDK 문서 4절).
    ///
    /// 노출은 **보유 claim 전체**다. 매칭이 지목한 것만 그리면 verifier 가 요구하지 않은 항목을
    /// 사용자가 자발적으로 낼 길이 없어지고, 화면이 요청 범위를 그대로 따라가 버린다.
    /// 잠금은 매칭이 지목한 code — 그 판정에 DCQL 을 다시 읽지 않는다.
    private static func sdjwtDocument(
        _ cred: SdJwtCredentialItem,
        requiredCodes: Set<String>
    ) throws -> VpPresentationDocument {
        // consentItems 는 issuer JWT payload 를 그 자리에서 파싱한다 — 못 읽으면 05102 로 던진다.
        // 삼키지 않는다: 카드를 못 그린 채 제출하면 동의 없는 공개가 된다.
        let claims = Self.sdjwtClaims(try cred.consentItems, requiredCodes: requiredCodes)
        return VpPresentationDocument(
            credentialId: cred.id,
            // 제목 규칙은 목록·상세와 공유 — SdJwtClaimDisplay 참조.
            title: SdJwtClaimDisplay.title(of: cred),
            claims: claims,
            // 상위가 REQUIRED 면 하위 code 도 함께 나가야 한다 — 트리에서 다시 거둬 하위까지 담는다.
            requiredCodes: Self.requiredCodes(in: claims),
            // 발급 시 바인딩된 키 — 제출 인증수단은 이 값이 정한다 (사용자 선택 불가).
            bindingKeyId: cred.kid
        )
    }

    /// `consentItems` → 화면 행. 걸러낼 항목·중첩 판정·순서는 상세화면과 **같은 규칙**을 쓴다
    /// (`SdJwtClaimDisplay.consentRows`). 여기서는 그 결과에 REQUIRED 여부만 얹는다.
    ///
    /// **중첩은 통째로 움직인다**(PRES-B-03) — 상위 체크박스 하나가 서브트리 전체를 토글하고 하위는
    /// 개별 체크박스를 갖지 않는다. 하위의 `code` 는 제출 집합을 만들 때만 쓴다.
    ///
    /// 필수는 **상위에서만 내려오고 하위로 전파된다** — 상위가 REQUIRED 면 그 서브트리 전체가
    /// REQUIRED 다. (하위만 REQUIRED 인 조합은 서버가 내리지 않는다.)
    private static func sdjwtClaims(_ items: [SdJwtConsentItem],
                                    requiredCodes: Set<String>) -> [VpPresentationClaim] {
        SdJwtClaimDisplay.consentRows(items).map { row in
            let required = requiredCodes.contains(row.item.code)
            let nested = row.nested.map { child in
                VpPresentationClaim(code: child.code,
                                    label: child.claimName,
                                    value: SdJwtClaimDisplay.value(of: child),
                                    required: required || requiredCodes.contains(child.code))
            }
            let rideAlong = row.rideAlong.map {
                VpPresentationClaim(code: nil,
                                    label: $0.label,
                                    value: ImageClaim.claimValue(name: $0.label, text: $0.value),
                                    required: required)
            }
            let children = nested + rideAlong
            return VpPresentationClaim(
                code: row.item.code,
                label: row.item.claimName,
                // 그룹(복합값)은 값 자리가 비어 있다 — 값은 하위 행이 그린다.
                value: children.isEmpty ? SdJwtClaimDisplay.value(of: row.item) : .text(""),
                required: required,
                children: children
            )
        }
    }

    /// mDoc 카드 한 장 — SD-JWT 와 같은 근거(`consentItems`)를 쓴다. code 는 SDK 가 만든 값이고
    /// 앱은 `네임스페이스`·`원소이름` 을 화면에 그리는 데만 쓴다(그 둘로 code 를 조립하지 않는다).
    ///
    /// 노출은 보유 원소 전체, REQUIRED 는 매칭이 지목한 code. 값이 비어 있는 원소도 거르지 않는다
    /// (결정 2026-08-11) — 발급 서버가 빈 값을 실어 보내는 동안에도 무엇이 나가는지는 그대로 보인다.
    private static func mdocDocument(
        _ cred: MdocCredentialItem,
        requiredCodes: Set<String>
    ) -> VpPresentationDocument {
        let claims = Self.mdocClaims(cred.consentItems, requiredCodes: requiredCodes)
        return VpPresentationDocument(
            credentialId: cred.id,
            // 제목 규칙은 목록·상세와 공유 — MdocClaimDisplay 참조.
            title: MdocClaimDisplay.title(of: cred),
            claims: claims,
            requiredCodes: Self.requiredCodes(in: claims),
            // 발급 시 바인딩된 키 — SD-JWT 와 같이 제출 인증수단을 이 값이 정한다.
            bindingKeyId: cred.kid
        )
    }

    /// mDoc `consentItems` → 화면 행.
    ///
    /// `isAmbiguous` 는 걷어낸다 — 한 code 가 원소 두 개를 가리켜 제출 시 SDK 가 실패시키므로
    /// 지킬 수 없는 동의를 받지 않는다. 순서는 `consentItems` 가 정한 발급자 서명 순서를 그대로 쓴다
    /// (`Mdoc.namespaces` 를 직접 순회하면 화면을 열 때마다 항목이 재배열된다).
    ///
    /// **네임스페이스로 묶지 않고 평면으로 그린다.** 네임스페이스는 쪼갤 수 없는 묶음이 아니라
    /// 이름공간일 뿐이고(선택 공개의 단위는 원소 하나 = 다이제스트 하나), REQUIRED/OPTIONAL 섹션이
    /// 그 묶음을 가로지르기 때문이다. 라벨은 `elementIdentifier` 원문 그대로 쓴다 — 발급자가 실어
    /// 보내는 원소 이름에 네임스페이스가 이미 들어 있어, 접두하면 두 번 나온다.
    private static func mdocClaims(_ items: [MdocConsentItem],
                                   requiredCodes: Set<String>) -> [VpPresentationClaim] {
        items.filter { !$0.isAmbiguous }
            .map { Self.mdocClaim($0, requiredCodes: requiredCodes) }
    }

    /// 한 원소 — 복합값(array/map)은 접이식 그룹으로 펼친다. 하위는 원소 하나의 값 안쪽이라
    /// 따로 뺄 수 없다(다이제스트가 원소 단위) → 표시 전용(`code == nil`).
    private static func mdocClaim(_ item: MdocConsentItem,
                                  requiredCodes: Set<String>) -> VpPresentationClaim {
        let required = requiredCodes.contains(item.code)
        let children = MdocClaimDisplay.childRows(item.value).map {
            VpPresentationClaim(code: nil, label: $0.label, value: $0.value, required: required)
        }
        return VpPresentationClaim(
            code: item.code,
            label: item.elementIdentifier,
            value: children.isEmpty
                ? MdocClaimDisplay.claimValue(name: item.elementIdentifier, value: item.value)
                : .text(""),
            required: required,
            children: children
        )
    }

    /// 노출 트리에서 **항상 제출되는 code** 를 거둔다 — REQUIRED 행과 그 하위 전부.
    /// 상위가 REQUIRED 면 하위도 REQUIRED 로 내려오므로(전파), 이 순회 하나로 하위 code 까지 모인다.
    private static func requiredCodes(in claims: [VpPresentationClaim]) -> Set<String> {
        var codes: Set<String> = []
        for claim in claims {
            if claim.required, let code = claim.code { codes.insert(code) }
            codes.formUnion(requiredCodes(in: claim.children))
        }
        return codes
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
    /// 합집합으로 두는 건 SDK 계약이다 — 매칭이 준 claimCodes 를 하나라도 빠뜨리면 제출이 거부된다
    /// (`invalidSelectedCredentials`). 화면에서 뺀 평문 claim 처럼 그리지 못한 필수 code 가 여기서
    /// 되살아난다. 필수는 verifier 가 요구한 것이므로 넘치는 공개도 아니다.
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
            // 화면은 **선택된 후보 1건만** 담아 보낸다 — 키가 없으면 사용자가 고르지 않은 후보다.
            // (예전엔 "화면에 없던 것"으로 보고 통과시켰는데, 후보가 여럿인 화면이 생기면서
            //  고르지 않은 카드까지 함께 나가게 된다.)
            guard let checked = selectedCodes[mc.credentialId] else { return nil }
            // 체크 0건이어도 REQUIRED(`claimCodes`)가 있으면 제출한다 — OPTIONAL 기본값이 해제라
            // "체크 0건"이 곧 "안 내겠다"가 아니다.
            let codes = checked.union(mc.claimCodes)
            guard !codes.isEmpty else { return nil }
            return MatchedCredential(queryId: mc.queryId,
                                     credentialId: mc.credentialId,
                                     claimCodes: Array(codes))
        }
    }

}

// MARK: - 이식한 SDK OID4VPProtocol API (static · 이름/시그니처 그대로 · 상태 없음)
//
// OID4VCI(`IssueOID4VcProtocol`) 와 같은 이유·같은 방식의 이식이다. 두 API 모두 앱이 쥔 정보
// (인가요청 URI / 조립 끝난 form body)로 HTTP 를 한 번 치고 결과를 검증하는 얇은 계층이라
// SDK 표면에 묶어 둘 이유가 없다. 발급·서명·봉인 같은 본체는 그대로 SDK 몫이다.
//
// JWS 파싱·ES256 검증은 SDK `JWS` 정본을 그대로 쓴다(SD-JWT 처리와 같은 코드). 검증 키는 헤더
// `kid` 가 가리키는 verifier DID Document 에서 받으므로 서명 무결성뿐 아니라 **서명자 신원**까지
// 확인된다 — 근거가 요청 바깥(DID 레지스트리)에 있어야 신원이 성립한다(`JWSSignerVerifier`).
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

        // 서명 키는 **헤더의 `jwk` 가 아니라** `kid` 가 가리키는 verifier DID Document 에서 받는다.
        // `jwk` 는 요청자가 스스로 넣은 키라 "변조되지 않았다"까지만 말해 준다 — 그 키로 검증하면
        // 아무나 자기 키로 서명하고 `client_id`·`client_name` 에 원하는 기관명을 적어 동의를 받아낼 수
        // 있다. 그 값들은 그대로 제시 화면의 "Requesting Institution" 에 뜬다.
        // Status List 토큰과 같은 검증 경로다(`JWSSignerVerifier`).
        guard let kid = try jws.protectedHeader.kid else {
            throw OID4VPPresenterError.malformedJWS
        }
        try await JWSSignerVerifier.verify(jws: jws, kid: kid)

        // payload 는 snake_case — Jsonable 기본 디코더가 FromSnake 를 보고 변환해 준다.
        // (SDK `getPayload()` 는 internal 이라 payloadData 를 직접 디코딩한다.)
        return try AuthorizationRequest(from: jws.payloadData)
    }

    /// `createVpToken` 이 만들어 준 authorization response body 를 verifier 의 `response_uri` 로
    /// `application/x-www-form-urlencoded` POST 한다. body 조립·서명·JWE 봉인은 이미 끝난 상태다.
    /// - Returns: verifier 응답 본문과 HTTP 상태 코드.
    /// - Throws: 비-2xx 면 verifier 가 준 실패 이유를 담은 `AppError.server`, 그 형식을 못 읽으면
    ///   `OID4VPPresenterError.failedToSubmit`.
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
            // 상태코드만으로는 무엇이 거절됐는지 알 수 없다 — verifier 가 body 에 적어 준 실패 이유를
            // 살려서 던진다(`{error, errorDescription}`). 형식을 못 읽으면 상태코드로 폴백.
            if let serverError = AppError.server(from: data) {
                throw serverError
            }
            throw OID4VPPresenterError.failedToSubmit(statusCode)
        }
        return (data, statusCode)
    }
}
