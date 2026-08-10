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
import Observation
import DIDWalletSDK

// 발급/조회한 VC 와 그 부가정보(VCSchema, 상태)를 메모리에 보관하는 캐시.
// - credentials:    WalletAPI.getAllCredentials 결과 (SDK 모델). 재조회 없이 재사용.
// - zkpCredentials: WalletAPI.getAllZKPCredentials 결과. VC 와 페어이므로 함께 로드한다
//                   (ZKP 는 VC 단독 보유 위에만 존재 — ZKP 단독 케이스 없음).
// - schemaCache:    credentialSchema.id(URL) → VCSchema. title 반복 조회 비용 절감.
// - statusCache:    vcId → VCStatusEnum. vc-meta 반복 조회 비용 절감.
// - zkpSchemaCache: ZKPCredential.schemaId → ZKPCredentialSchema. ZKP 클레임 라벨(caption) 매핑용.
@Observable
final class CredentialStore {

    static let shared = CredentialStore()
    private init() {}

    private(set) var credentials: [VerifiableCredential] = []
    private(set) var zkpCredentials: [ZKPCredential] = []

    @ObservationIgnored private var schemaCache: [String: VCSchema] = [:]
    @ObservationIgnored private var statusCache: [String: VCStatusEnum] = [:]
    @ObservationIgnored private var zkpSchemaCache: [String: ZKPCredentialSchema] = [:]
    // SD-JWT 상태 — W3C `statusCache` 와 같은 주기(메인 진입 시 캐시 우선, 상세 진입 시 강제 재조회).
    // Status List Token 원문이나 압축 해제한 상태 배열은 보관하지 않는다 — 결과 enum 한 개만 남긴다.
    @ObservationIgnored private var sdJwtStatusCache: [String: StatusListStatus] = [:]
    // credentialId → Status List 위치. 상세 진입 시 재조회하려면 uri·idx 가 필요한데, 그 값은
    // 저장된 SD-JWT payload 에만 있어 목록 로딩 때 함께 보관한다.
    @ObservationIgnored private var sdJwtStatusRefs: [String: StatusListVerifier.Reference] = [:]

    /// 상태 캐시를 비운다 — 다음 목록 로딩이 Status List / vc-meta 를 다시 조회하게 한다.
    /// 상태는 서버에서 언제든 바뀌므로(폐기·정지) 앱이 떠 있는 내내 첫 조회값을 붙들고 있으면 안 된다.
    /// 백그라운드에서 돌아올 때 호출한다. `sdJwtStatusRefs`(uri·idx)는 크리덴셜에 고정된 값이라 남긴다.
    func invalidateStatusCache() {
        statusCache.removeAll()
        sdJwtStatusCache.removeAll()
    }

    /// 지갑의 전체 VC + ZKP 크레덴셜을 다시 읽어 메모리에 반영. 저장된 VC 가 없으면 둘 다 빈 배열.
    /// VC·ZKP 는 페어라 같은 wallet token 으로 한 번에 로드한다
    /// (`getAllZKPCredentials` 도 `.LIST_VC` 토큰을 허용).
    func reloadCredentials() async throws {
        guard WalletAPI.shared.isAnyCredentialsSaved else {
            credentials = []
            zkpCredentials = []
            return
        }
        let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .LIST_VC)
        credentials = (try WalletAPI.shared.getAllCredentials(hWalletToken: hWalletToken)) ?? []
        zkpCredentials = (try WalletAPI.shared.getAllZKPCredentials(hWalletToken: hWalletToken)) ?? []
    }

    /// schema id(URL) 로 VCSchema 조회 — 캐시에 있으면 그대로, 없으면 GET 후 캐시.
    func schema(id: String) async throws -> VCSchema {
        if let cached = schemaCache[id] {
            return cached
        }
        let schema: VCSchema = try await HttpClient.sendGetRequest(urlString: id)
        schemaCache[id] = schema
        return schema
    }

    /// ZKPCredential.schemaId 로 ZKPCredentialSchema 조회 — 캐시 우선, 없으면 GET 후 캐시.
    /// ZKP 클레임 키(`namespace.id.label`)를 사람이 읽을 caption 으로 바꾸는 데 쓴다.
    func zkpSchema(id: String) async throws -> ZKPCredentialSchema {
        if let cached = zkpSchemaCache[id] {
            return cached
        }
        let schema = try await CommunicationClient.getZKPCredentialSchama(
            hostUrlString: URLs.API_URL,
            id: id
        )
        zkpSchemaCache[id] = schema
        return schema
    }

    /// vcId 의 발급 상태(ACTIVE/INACTIVE/REVOKED) 조회.
    /// 기본은 캐시 우선이며, `forceRefresh` 면 캐시를 무시하고 vc-meta 를 새로 조회한다
    /// (폐기처럼 현재 서버 상태가 중요한 경우 사용). 어느 쪽이든 결과는 캐시에 반영.
    /// 응답의 vcMeta 는 multibase 인코딩이라 decode 후 VCMeta 로 역직렬화한다.
    func status(forVcId vcId: String, forceRefresh: Bool = false) async throws -> VCStatusEnum {
        if !forceRefresh, let cached = statusCache[vcId] {
            return cached
        }
        let urlString = "\(URLs.API_URL)/api-gateway/api/v1/vc-meta?vcId=\(vcId)"
        let vo: VCMetaVO = try await HttpClient.sendGetRequest(urlString: urlString)
        let meta = try VCMeta(from: try MultibaseUtils.decode(encoded: vo.vcMeta))
        statusCache[vcId] = meta.status
        return meta.status
    }

    /// 상세화면 진입 시 호출 — 해당 크리덴셜의 상태를 새로 조회해 표시용 상태로 변환.
    /// 만료 여부는 발급 시 고정이므로 기존 표시값을 따른다. 조회 실패 시 기존 상태를 그대로 반환.
    /// SD-JWT 는 서버 vc-meta 가 아니라 Status List 로 판정한다.
    func refreshedStatus(for credential: Credential) async -> CredentialStatus {
        if credential.badge == .sdJwt {
            return await refreshedSDJWTStatus(for: credential)
        }
        guard let fresh = try? await status(forVcId: credential.id, forceRefresh: true) else {
            return credential.status
        }
        switch fresh {
        case .REVOKED:
            // 폐기는 SD-JWT(Status List INVALID)와 같은 표시로 맞춘다.
            return .expired
        case .INACTIVE:
            return .inactive
        case .ACTIVE:
            return credential.status == .expired ? .expired : .active
        }
    }

    /// SD-JWT 상세 진입 — 만료된 카드는 조회하지 않고, 그 외에는 캐시를 무시하고 Status List 를
    /// 새로 조회한다. 실패하면 안내 토스트 후 만료일 기준 표시(기존 상태)를 유지한다.
    private func refreshedSDJWTStatus(for credential: Credential) async -> CredentialStatus {
        guard credential.status != .expired,
              let reference = sdJwtStatusRefs[credential.id]
        else {
            return credential.status
        }
        do {
            let status = try await StatusListVerifier.status(for: reference)
            sdJwtStatusCache[credential.id] = status
            return Self.displayStatus(status)
        } catch {
            sdJwtStatusCache[credential.id] = nil
            OverlayManager.shared.showToast(message: Self.statusCheckFailureMessage)
            return credential.status
        }
    }

    /// Status List 상태 → 표시용 상태. RESERVED 는 조회 단계에서 실패로 걸러진다.
    private static func displayStatus(_ status: StatusListStatus) -> CredentialStatus {
        switch status {
        case .valid:     return .active
        case .invalid:   return .expired
        case .suspended: return .inactive
        case .reserved:  return .expired
        }
    }

    /// 조회·검증 실패 안내. 상태를 "유효"로 대체하지 않고 만료일 기준 표시로 물러났음을 알린다.
    static let statusCheckFailureMessage = "Couldn't check the credential status."

    /// 지갑 VC 를 다시 읽어 화면 표시용 [Credential] 로 매핑해 반환.
    /// - 전체 조회(reloadCredentials)가 실패하면 빈 배열 — 메인 진입 자체는 막지 않는다.
    /// - 개별 VC 의 schema/status 조회 실패는 기본값으로 흡수한다.
    func loadCredentials() async -> [Credential] {
        do {
            try await reloadCredentials()
        } catch {
            return []
        }
        // SD-JWT 로드는 별도 저장소·토큰이라 W3C 매핑과 독립 → 먼저 시작해 루프와 겹친다.
        async let sdjwtCredentials = loadSDJWTCredentials()

        var result: [Credential] = []
        for vc in credentials {
            let zkpCred = zkpCredential(forVcId: vc.id)
            // 한 VC 의 schema/status/zkpSchema 조회는 서로 독립 → 동시에 시작해 네트워크 왕복을 겹친다
            // (콜드캐시에서 VC 당 최대 3회 직렬 왕복이 스플래시를 붙잡던 문제 완화).
            async let vcSchemaTask = schema(id: vc.credentialSchema.id)
            async let vcStatusTask = status(forVcId: vc.id)
            async let zkpSchemaTask = zkpSchemaIfPresent(zkpCred)

            let vcSchema = try? await vcSchemaTask
            let vcStatus = (try? await vcStatusTask) ?? .ACTIVE
            let zkpSchema = await zkpSchemaTask
            result.append(Self.makeCredential(
                vc: vc, schema: vcSchema, status: vcStatus, zkp: zkpCred, zkpSchema: zkpSchema))
        }
        // OID4VCI 로 발급된 SD-JWT 는 W3C 와 저장소가 분리돼 있어 따로 읽어 합친다.
        result.append(contentsOf: await sdjwtCredentials)
        return result
    }

    /// ZKP 페어가 있으면 그 스키마(클레임 caption 매핑용)를 조회, 없으면 nil. 조회 실패도 nil.
    private func zkpSchemaIfPresent(_ zkpCred: ZKPCredential?) async -> ZKPCredentialSchema? {
        guard let zkpCred else { return nil }
        return try? await zkpSchema(id: zkpCred.schemaId)
    }

    /// OID4VCI 로 발급된 SD-JWT 크레덴셜을 화면 표시용 `[Credential]` 로 매핑.
    /// W3C(`WalletAPI`/`vc.vc`)와 별개 저장소(`WalletAPI` OID4VC/`oid4vc_credential.vc`)라
    /// 별도로 읽는다. SD-JWT 외 포맷(mdoc/unknown)은 표시에서 제외(Phase 2).
    /// ⚠️ 가져오는 주체는 후속 변경 예정(메인 진입 캐시 일원화) — 매핑 로직은 그대로 재사용.
    /// 저장된 SD-JWT 를 표시용 `Credential` 로 변환한다.
    ///
    /// 상태는 **만료일 우선** — `exp` 가 지났으면 그대로 expired 로 두고 Status List 를 조회하지
    /// 않는다. 유효한 카드만 조회하며, 캐시에 있으면 재조회하지 않는다(W3C `statusCache` 와 같은 주기).
    /// 조회·검증 실패는 유효로 대체하지 않고 만료일 기준 표시로 물러난 뒤 토스트로 알린다 —
    /// 여러 장이 실패해도 이 회차에 한 번만 띄운다.
    func loadSDJWTCredentials() async -> [Credential] {
        guard let hWalletToken = try? await TokenGenerator.requestWalletToken(purpose: .LIST_VC),
              let issued = try? WalletAPI.shared.getAllOID4VCs(hWalletToken: hWalletToken) else { return [] }

        // [1] 표시 데이터를 먼저 만들고, 조회가 필요한 항목(만료 안 됨 + status 참조 있음 + 캐시 없음)만 모은다.
        var credentials: [Credential] = []
        var pending: [String: StatusListVerifier.Reference] = [:]
        for item in issued {
            guard let payload = Self.sdJwtPayload(item),
                  let credential = Self.makeSDJWTCredential(item, payload: payload)
            else { continue }

            guard credential.status != .expired,
                  let reference = StatusListVerifier.reference(from: payload)
            else {
                credentials.append(credential)
                continue
            }
            sdJwtStatusRefs[item.id] = reference

            if let cached = sdJwtStatusCache[item.id] {
                credentials.append(credential.with(status: Self.displayStatus(cached)))
            } else {
                pending[item.id] = reference
                credentials.append(credential)
            }
        }
        guard !pending.isEmpty else { return credentials }

        // [2] 한 번에 조회 — 같은 리스트를 가리키는 카드들은 토큰을 한 번만 받아 검증한다.
        let statuses = await StatusListVerifier.statuses(for: pending)
        var statusCheckFailed = false
        let resolved: [Credential] = credentials.map { credential in
            guard let outcome = statuses[credential.id] else { return credential }
            switch outcome {
            case .success(let status):
                sdJwtStatusCache[credential.id] = status
                return credential.with(status: Self.displayStatus(status))
            case .failure:
                statusCheckFailed = true
                return credential   // 만료일 기준 표시 유지
            }
        }
        if statusCheckFailed {
            OverlayManager.shared.showToast(message: Self.statusCheckFailureMessage)
        }
        return resolved
    }

    /// vcId 와 짝지어진 ZKP 크레덴셜 — 없으면 nil.
    /// `ZKPCredential.credentialId` 가 `VerifiableCredential.id` 와 동일 키.
    func zkpCredential(forVcId vcId: String) -> ZKPCredential? {
        zkpCredentials.first { $0.credentialId == vcId }
    }

    // MARK: - VerifiableCredential → Credential 매핑

    private static func makeCredential(vc: VerifiableCredential,
                                       schema: VCSchema?,
                                       status: VCStatusEnum,
                                       zkp zkpCred: ZKPCredential?,
                                       zkpSchema: ZKPCredentialSchema?) -> Credential {
        // VC 클레임 → 평면 .row 목록 (VCSchema namespace 그룹화는 후속 작업).
        // image 타입은 인코딩된 value 를 Data 로 디코드해 비율 유지 렌더링에 넘긴다.
        let claims: [ClaimEntry] = vc.credentialSubject.claims.map { claim in
            let value: ClaimValue = claim.type == .image
                ? (decodeImage(claim.value).map(ClaimValue.image) ?? .text(claim.value))
                : .text(claim.value)
            return ClaimEntry(kind: .row(label: claim.caption, value: value))
        }
        return Credential(
            id: vc.id,
            name: schema?.title ?? vc.id,
            badge: .vc,
            issuer: vc.issuer.name ?? vc.issuer.id,
            issued: displayDate(vc.issuanceDate),
            valid: displayDate(vc.validUntil),
            status: displayStatus(status, validUntil: vc.validUntil),
            zkp: zkpCred != nil,
            claims: claims,
            zkpClaims: zkpClaimItems(from: zkpCred, schema: zkpSchema)
        )
    }

    // MARK: - OID4VCICredential(SD-JWT) → Credential 매핑

    /// 저장된 SD-JWT 의 issuer-signed JWT payload. SD-JWT 포맷이 아니면 nil(표시 제외).
    /// 메타(iss/iat/exp)와 status 참조를 같은 payload 에서 읽으므로 파싱은 한 번만 한다.
    private static func sdJwtPayload(_ issued: SdJwtCredentialItem) -> [String: Any]? {
        switch issued.format {
        case .sdJwtVc: break
        default: return nil   // msoMdoc/vcdm 은 표시 제외 — Phase 2.
        }
        return (try? SimpleJWTDecoder.parse(issued.sdjwt.credentialJwt))?.payload ?? [:]
    }

    /// 저장된 SD-JWT 한 건을 표시용 `Credential` 로 변환.
    /// 메타는 issuer-signed JWT payload(vct/iss/iat/exp)에서, 클레임은 disclosure 에서 뽑는다.
    /// 여기서의 상태는 **만료일 기준**이며, 유효한 카드의 폐기·정지 여부는 호출측이 Status List 로
    /// 판정해 덮어쓴다.
    private static func makeSDJWTCredential(_ issued: SdJwtCredentialItem,
                                            payload: [String: Any]) -> Credential? {
        let sdjwt = issued.sdjwt

        // disclosure(선택공개 항목) → 클레임 목록. 값이 복합(object/array)이면 접이식 .group,
        // 스칼라면 단일 .row 로 매핑한다(한 단계 중첩; 더 깊은 값은 jsonString 으로 생략).
        let claims: [ClaimEntry] = sdjwt.disclosures.map { disclosure in
            let label = disclosure.claimName ?? ""
            if let items = subItems(disclosure.claimValue) {
                return ClaimEntry(kind: .group(title: label, items: items))
            }
            return ClaimEntry(kind: .row(label: label, value: .text(SdJwtClaimDisplay.scalarString(disclosure.claimValue))))
        }

        // exp 가 지났으면 expired — 이 경우 Status List 는 조회하지 않는다.
        let isExpired = epochDate(payload["exp"]).map { $0 < Date() } ?? false

        return Credential(
            id: issued.id,
            // 제목 규칙은 VP 제출 카드와 공유 — SdJwtClaimDisplay 참조.
            name: SdJwtClaimDisplay.title(of: issued),
            badge: .sdJwt,
            issuer: (payload["iss"] as? String) ?? "",
            issued: epochDisplay(payload["iat"]),
            valid: epochDisplay(payload["exp"]),
            status: isExpired ? .expired : .active,
            claims: claims
        )
    }

    /// 복합값(object/array)이면 접이식 그룹의 하위 항목 목록으로, 스칼라면 nil(단일 행으로 표시).
    /// object → 키별 한 행, array → 1-based 인덱스 라벨. 비어 있으면 nil(빈 그룹 방지).
    /// 펼침 규칙은 `SdJwtClaimDisplay` 공유 — VP 요청화면(OID4VPPresenter)과 어긋나지 않게.
    private static func subItems(_ json: JSON) -> [ClaimItem]? {
        let rows = SdJwtClaimDisplay.childRows(json)
        guard !rows.isEmpty else { return nil }
        return rows.map { ClaimItem(label: $0.label, value: .text($0.value)) }
    }

    /// JWT 수치 클레임(iat/exp, epoch seconds) → Date. 숫자가 아니면 nil.
    private static func epochDate(_ any: Any?) -> Date? {
        guard let number = any as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: number.doubleValue)
    }

    /// epoch seconds → "dd MMM yyyy" (W3C 의 displayDate 와 동일 표기).
    private static func epochDisplay(_ any: Any?) -> String? {
        guard let date = epochDate(any) else { return nil }
        return dateFormatter.string(from: date)
    }

    /// 페어 ZKP 크레덴셜의 values → ClaimItem 목록. key 정렬로 표시 순서를 고정한다.
    /// 라벨은 스키마의 caption(`namespace.id.label` → caption)으로 치환, 스키마 없거나 미매칭이면 raw 키.
    private static func zkpClaimItems(from zkp: ZKPCredential?,
                                      schema: ZKPCredentialSchema?) -> [ClaimItem] {
        guard let zkp else { return [] }
        let captions = schema?.captionMap ?? [:]
        return zkp.values
            .sorted { $0.key < $1.key }
            .map { ClaimItem(label: captions[$0.key] ?? $0.key, value: .text($0.value.raw)) }
    }

    /// 이미지 클레임 value 디코드 — base64 우선, 실패 시 multibase.
    private static func decodeImage(_ encoded: String) -> Data? {
        if let data = Data(base64Encoded: encoded) {
            return data
        }
        return try? MultibaseUtils.decode(encoded: encoded)
    }

    /// ISO8601 문자열 → "dd MMM yyyy". 파싱 실패 시 nil.
    private static func displayDate(_ iso: String) -> String? {
        guard let date = isoParser.date(from: iso) else { return nil }
        return dateFormatter.string(from: date)
    }

    /// VC 상태 + 만료일 → 화면 표시용 상태.
    /// REVOKED 는 CredentialStatus 에 대응 케이스가 없어 .inactive 로 흡수한다.
    private static func displayStatus(_ status: VCStatusEnum,
                                      validUntil: String) -> CredentialStatus {
        switch status {
        case .REVOKED:
            // 폐기 표시는 SD-JWT(Status List INVALID)와 같은 뱃지로 맞춘다.
            return .expired
        case .INACTIVE:
            return .inactive
        case .ACTIVE:
            if let until = isoParser.date(from: validUntil), until < Date() {
                return .expired
            }
            return .active
        }
    }

    private static let isoParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // 목록(MainView)·상세(CredentialHero)의 ISSUED / VALID UNTIL 표기를 만드는 단일 포맷터.
    // 일(day)은 한 자리도 0 을 채운다 — 카드가 세로로 쌓일 때 자릿수가 흔들리지 않게.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd MMM yyyy"
        return formatter
    }()
}

// vc-meta 응답 — vcMeta 는 multibase 인코딩된 VCMeta 문자열.
private struct VCMetaVO: Jsonable {
    let vcId: String
    let vcMeta: String
}
