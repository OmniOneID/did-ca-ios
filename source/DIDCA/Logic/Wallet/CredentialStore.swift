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
    /// OID4VCI 로 발급된 보유분(SD-JWT·mDoc 이 한 목록으로 섞여 온다). W3C 와 저장소가 분리돼 있어
    /// 따로 읽지만, 읽는 시점은 `reloadCredentials()` 한 곳으로 모은다 — 목록이 두 저장소를 서로
    /// 다른 시점의 스냅샷으로 그리면 발급 직후 새 카드가 한 박자 늦게 나타난다.
    /// ⚠️ OID4VP 매칭은 이 캐시를 쓰지 않는다 — 제출 대상은 그 자리에서 새로 읽는다.
    private(set) var oid4vcCredentials: [any CredentialItem] = []

    @ObservationIgnored private var schemaCache: [String: VCSchema] = [:]
    @ObservationIgnored private var statusCache: [String: VCStatusEnum] = [:]
    @ObservationIgnored private var zkpSchemaCache: [String: ZKPCredentialSchema] = [:]
    // Status List 상태(SD-JWT·mDoc 공용) — W3C `statusCache` 와 같은 주기(메인 진입 시 캐시 우선,
    // 상세 진입 시 강제 재조회). Status List Token 원문이나 압축 해제한 상태 배열은 보관하지 않는다
    // — 결과 enum 한 개만 남긴다.
    @ObservationIgnored private var statusListCache: [String: StatusListStatus] = [:]
    // credentialId → Status List 위치. 상세 진입 시 재조회하려면 uri·idx 가 필요한데, 그 값은
    // 저장된 크리덴셜에서만 나오므로 목록 로딩 때 함께 보관한다.
    @ObservationIgnored private var statusListRefs: [String: StatusListVerifier.Reference] = [:]

    /// 상태 캐시를 비운다 — 다음 목록 로딩이 Status List / vc-meta 를 다시 조회하게 한다.
    /// 상태는 서버에서 언제든 바뀌므로(폐기·정지) 앱이 떠 있는 내내 첫 조회값을 붙들고 있으면 안 된다.
    /// 백그라운드에서 돌아올 때 호출한다. `statusListRefs`(uri·idx)는 크리덴셜에 고정된 값이라 남긴다.
    func invalidateStatusCache() {
        statusCache.removeAll()
        statusListCache.removeAll()
    }

    /// 지갑 보유분 전체를 다시 읽어 메모리에 반영 — W3C VC + ZKP + OID4VC(SD-JWT·mDoc).
    /// 저장소는 둘로 갈려 있지만 토큰은 하나면 되고(`.LIST_VC` 가 양쪽 조회를 모두 허용한다),
    /// 한 번에 읽어야 목록이 같은 시점의 스냅샷이 된다.
    ///
    /// OID4VC 조회 실패는 삼킨다 — 그쪽 저장소가 비어 있거나 읽히지 않아도 W3C 목록까지 사라질
    /// 이유는 없다(그 반대도 마찬가지로, W3C 조회 실패는 호출측이 빈 목록으로 흡수한다).
    func reloadCredentials() async throws {
        guard WalletAPI.shared.isAnyCredentialsSaved || WalletAPI.shared.isAnyOID4VCSaved else {
            credentials = []
            zkpCredentials = []
            oid4vcCredentials = []
            return
        }
        let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .LIST_VC)

        if WalletAPI.shared.isAnyCredentialsSaved {
            credentials = (try WalletAPI.shared.getAllCredentials(hWalletToken: hWalletToken)) ?? []
            zkpCredentials = (try WalletAPI.shared.getAllZKPCredentials(hWalletToken: hWalletToken)) ?? []
        } else {
            credentials = []
            zkpCredentials = []
        }

        oid4vcCredentials = WalletAPI.shared.isAnyOID4VCSaved
            ? ((try? WalletAPI.shared.getAllOID4VCs(hWalletToken: hWalletToken)) ?? [])
            : []
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
    /// SD-JWT·mDoc 은 서버 vc-meta 가 아니라 Status List 로 판정한다.
    func refreshedStatus(for credential: Credential) async -> CredentialStatus {
        // SD-JWT·mDoc 은 vc-meta 가 아니라 Status List 로 판정한다 — 참조가 있는 카드만 조회한다.
        if credential.badge == .sdJwt || credential.badge == .mDoc {
            return await refreshedStatusListStatus(for: credential)
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

    /// SD-JWT·mDoc 상세 진입 — 만료된 카드는 조회하지 않고, 그 외에는 캐시를 무시하고 Status List 를
    /// 새로 조회한다. 참조가 없으면(Status List 미적용분) 만료일 기준 표시를 그대로 둔다.
    /// 실패하면 안내 토스트 후 만료일 기준 표시(기존 상태)를 유지한다.
    private func refreshedStatusListStatus(for credential: Credential) async -> CredentialStatus {
        guard credential.status != .expired,
              let reference = statusListRefs[credential.id]
        else {
            return credential.status
        }
        do {
            let status = try await StatusListVerifier.status(for: reference)
            statusListCache[credential.id] = status
            return Self.displayStatus(status)
        } catch {
            // 캐시를 지우지 않는다 — 조회 실패의 폴백이 **마지막으로 조회한 상태**이고,
            // 그게 없을 때만 만료일 기준 표시로 물러난다. 지우면 첫 실패에 폴백이 사라진다.
            OverlayManager.shared.showToast(message: Self.statusCheckFailureMessage)
            return statusListCache[credential.id].map(Self.displayStatus) ?? credential.status
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

    // MARK: - 제출 후보 판정 (PRES-B-06)

    /// 제출 후보로 올릴 수 있는 크리덴셜을 **한 번에** 가린다 — 돌려주는 것은 ACTIVE 인 것의 id 집합.
    /// Inactive·Expired 는 단일/복수 판정과 옵션 목록에서 모두 제외된다.
    ///
    /// **후보를 한 건씩 판정하지 않는다.** 같은 Status List 를 가리키는 후보들이 같은 토큰을 후보
    /// 수만큼 내려받게 되는데, 낭비인 것보다 판정이 갈리는 것이 문제다 — 그중 일부만 실패하면 같은
    /// 리스트를 근거로 하는 후보들이 서로 다른 사다리 단계로 판정돼, 사용자에게는 같은 발급기관 카드
    /// 중 하나만 목록에서 사라진 모습이 된다. 묶음 조회는 목록 표시(`oid4vcDisplayCredentials`)가
    /// 쓰는 것과 같은 경로다.
    ///
    /// 판정 사다리는 세 단계이고, **실패를 ACTIVE 로 승격하지 않는다** — 2·3 은 이미 알고 있는
    /// 사실로 물러나는 것이지 모르는 것을 유효로 치는 게 아니다.
    /// 1. Status List 를 **새로** 조회한다 (제출은 그 자리의 사실이 중요하므로 캐시를 먼저 보지 않는다)
    /// 2. 조회·참조 읽기가 실패하면 **마지막으로 조회한 상태**로 판정한다
    /// 3. 그것도 없으면 **만료일과 현재 시각**을 비교한다
    ///
    /// 못 읽는 크리덴셜과 앱이 표시할 줄 모르는 포맷은 집합에서 빠진다(= 후보가 아니다).
    func submittableIds(among items: [any CredentialItem]) async -> Set<String> {
        let candidates = items.compactMap(Self.submissionCandidate)

        // [1] 조회할 것만 모은다 — 만료분은 조회 없이 탈락이고, 참조가 없으면 조회할 것이 없다.
        var pending: [String: StatusListVerifier.Reference] = [:]
        for candidate in candidates where candidate.expiryStatus != .expired {
            if let reference = candidate.reference {
                pending[candidate.credentialId] = reference
            }
        }
        // [2] 같은 uri 를 가리키는 후보는 토큰을 한 번만 받아 인덱스별 비트만 읽는다.
        let statuses = pending.isEmpty
            ? [:]
            : await StatusListVerifier.statuses(for: pending)

        var submittable: Set<String> = []
        for candidate in candidates {
            guard candidate.expiryStatus != .expired else { continue }

            // [3-1] 새 조회 성공 — 판정 근거는 이것 하나다.
            if case .success(let status) = statuses[candidate.credentialId] {
                statusListCache[candidate.credentialId] = status
                if Self.displayStatus(status) == .active {
                    submittable.insert(candidate.credentialId)
                }
                continue
            }
            // Status List 미적용분 — 확인할 상태가 없고 만료도 아니다. (참조를 못 읽은 것과 다르다.)
            if candidate.reference == nil, !candidate.referenceUnreadable {
                submittable.insert(candidate.credentialId)
                continue
            }
            // [3-2] 조회·참조 읽기 실패 → 마지막으로 조회한 상태.
            if let cached = statusListCache[candidate.credentialId] {
                if Self.displayStatus(cached) == .active {
                    submittable.insert(candidate.credentialId)
                }
                continue
            }
            // [3-3] 아는 상태가 없다 → 만료일 기준.
            if candidate.expiryStatus == .active {
                submittable.insert(candidate.credentialId)
            }
        }
        return submittable
    }

    /// 판정 재료 — 실물에서 id·만료일 기준 상태·Status List 참조를 뽑는다.
    ///
    /// `reference == nil` 은 두 가지 사건을 겸하므로 `referenceUnreadable` 로 갈라 둔다.
    /// 참조가 애초에 없는 것(Status List 미적용분)은 확인할 상태가 없다는 뜻이고, 읽다 실패한 것은
    /// 확인해야 할 상태를 확인하지 못했다는 뜻이라 폴백 사다리를 타야 한다.
    private static func submissionCandidate(_ item: any CredentialItem) -> SubmissionCandidate? {
        switch item {
        case let item as SdJwtCredentialItem:
            // 표시 매핑을 그대로 쓴다 — 거기서 나오는 상태가 곧 3단계(만료일 기준)다.
            guard let payload = sdJwtPayload(item),
                  let credential = makeSDJWTCredential(item, payload: payload)
            else {
                return nil              // 못 읽는 크리덴셜은 후보가 아니다
            }
            var reference: StatusListVerifier.Reference?
            var unreadable = false
            do { reference = try item.status } catch { unreadable = true }
            return SubmissionCandidate(credentialId: credential.id,
                                       expiryStatus: credential.status,
                                       reference: reference,
                                       referenceUnreadable: unreadable)

        case let item as MdocCredentialItem:
            let credential = makeMdocCredential(item)
            // mDoc 은 `Mdoc.parse` 가 이미 MSO 를 풀어 둬서 참조 읽기가 실패할 여지가 없다.
            return SubmissionCandidate(credentialId: credential.id,
                                       expiryStatus: credential.status,
                                       reference: item.status,
                                       referenceUnreadable: false)

        default:
            return nil                  // 앱이 표시할 줄 모르는 포맷
        }
    }

    private struct SubmissionCandidate {
        let credentialId: String
        let expiryStatus: CredentialStatus
        let reference: StatusListVerifier.Reference?
        let referenceUnreadable: Bool
    }

    /// W3C VC 제출 후보 판정 — 사다리는 위와 같고 조회처만 `vc-meta` 다.
    func isSubmittable(w3c vc: VerifiableCredential) async -> Bool {
        guard Self.displayStatus(.ACTIVE, validUntil: vc.validUntil) != .expired else { return false }
        if let fresh = try? await status(forVcId: vc.id, forceRefresh: true) {
            return fresh == .ACTIVE
        }
        if let cached = statusCache[vc.id] {
            return cached == .ACTIVE
        }
        return true                     // 만료 안 됐고, 아는 상태가 없다
    }

    /// 발급자를 확인할 수 없을 때의 표시. SDK `issuerDid` 는 옵셔널이지만 저장된 크리덴셜에서는
    /// nil 이 나오지 않는다(발급 검증 자체가 그 DID 를 필요로 한다) — 빈 칸을 남기지 않기 위한 대비다.
    private static let unknownIssuer = "Unknown"

    /// 지갑 VC 를 다시 읽어 화면 표시용 [Credential] 로 매핑해 반환.
    /// - 전체 조회(reloadCredentials)가 실패하면 빈 배열 — 메인 진입 자체는 막지 않는다.
    /// - 개별 VC 의 schema/status 조회 실패는 기본값으로 흡수한다.
    func loadCredentials() async -> [Credential] {
        do {
            try await reloadCredentials()
        } catch {
            return []
        }
        // OID4VC(SD-JWT·mDoc) 매핑은 Status List 조회를 품고 있어 W3C 매핑과 독립 → 먼저 시작해
        // 아래 루프의 네트워크 왕복과 겹친다.
        async let oid4vcDisplay = oid4vcDisplayCredentials()

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
        // OID4VCI 발급분은 W3C 와 저장소가 분리돼 있어 따로 매핑해 합친다.
        result.append(contentsOf: await oid4vcDisplay)
        return result
    }

    /// ZKP 페어가 있으면 그 스키마(클레임 caption 매핑용)를 조회, 없으면 nil. 조회 실패도 nil.
    private func zkpSchemaIfPresent(_ zkpCred: ZKPCredential?) async -> ZKPCredentialSchema? {
        guard let zkpCred else { return nil }
        return try? await zkpSchema(id: zkpCred.schemaId)
    }

    /// OID4VCI 로 발급된 보유분(SD-JWT·mDoc)을 화면 표시용 `[Credential]` 로 매핑.
    /// 저장소는 두 포맷을 한 목록으로 돌려주므로 여기서 갈라 각자 규칙으로 옮기고, **저장 순서를
    /// 그대로 유지한다**(포맷별로 몰아 정렬하면 발급 순서가 화면에서 뒤섞인다).
    /// 앱이 표시할 줄 모르는 포맷은 조용히 건너뛴다.
    ///
    /// 상태는 **만료일 우선** — 만료됐으면 그대로 expired 로 두고 Status List 를 조회하지 않는다.
    /// 유효한 카드만 조회하며, 캐시에 있으면 재조회하지 않는다(W3C `statusCache` 와 같은 주기).
    /// 조회·검증 실패는 유효로 대체하지 않고 만료일 기준 표시로 물러난 뒤 토스트로 알린다 —
    /// 여러 장이 실패해도 이 회차에 한 번만 띄운다.
    ///
    /// SD-JWT·mDoc 모두 `status.status_list.{uri, idx}` 를 같은 규격으로 싣고, 참조는 SDK 가 읽어 준다.
    /// **nil 과 throw 는 다른 사건이다** — nil 은 "확인할 상태가 없다"(Status List 미적용분)이고,
    /// throw 는 참조가 깨져 "읽다 실패했다"다. 후자를 nil 로 삼키면 폐기 가능한 카드가 확인 없이
    /// 유효로 통과하므로, 조회 실패와 같은 취급(만료일 기준 표시 + 토스트)으로 올린다.
    private func oid4vcDisplayCredentials() async -> [Credential] {
        // [1] 표시 데이터를 먼저 만들고, 조회가 필요한 항목(만료 안 됨 + status 참조 있음 + 캐시 없음)만 모은다.
        var credentials: [Credential] = []
        var pending: [String: StatusListVerifier.Reference] = [:]
        var referenceUnreadable = false
        for stored in oid4vcCredentials {
            let credential: Credential
            let reference: StatusListVerifier.Reference?
            var readFailed = false

            switch stored {
            case let item as SdJwtCredentialItem:
                guard let payload = Self.sdJwtPayload(item),
                      let mapped = Self.makeSDJWTCredential(item, payload: payload)
                else { continue }
                credential = mapped
                do {
                    reference = try item.status
                } catch {
                    reference = nil
                    readFailed = true
                }

            case let item as MdocCredentialItem:
                credential = Self.makeMdocCredential(item)
                // mDoc 은 `Mdoc.parse` 가 이미 MSO 를 풀어 둬서 여기서 실패할 여지가 없다 —
                // 참조가 깨진 문서는 파싱 단계에서 걸려 목록에 아예 오지 않는다.
                reference = item.status

            default:
                continue
            }

            // 만료된 카드는 애초에 조회 대상이 아니다 — 참조를 못 읽었더라도 알릴 것이 없으므로
            // 실패 플래그를 세우지 않는다(만료 카드 때문에 매 로딩마다 토스트가 뜨는 것을 막는다).
            guard credential.status != .expired else {
                credentials.append(credential)
                continue
            }
            if readFailed {
                referenceUnreadable = true
            }
            guard let reference else {
                credentials.append(credential)
                continue
            }
            statusListRefs[credential.id] = reference

            if let cached = statusListCache[credential.id] {
                credentials.append(credential.with(status: Self.displayStatus(cached)))
            } else {
                pending[credential.id] = reference
                credentials.append(credential)
            }
        }
        guard !pending.isEmpty else {
            if referenceUnreadable {
                OverlayManager.shared.showToast(message: Self.statusCheckFailureMessage)
            }
            return credentials
        }

        // [2] 한 번에 조회 — 같은 리스트를 가리키는 카드들은 토큰을 한 번만 받아 검증한다.
        let statuses = await StatusListVerifier.statuses(for: pending)
        var statusCheckFailed = referenceUnreadable
        let resolved: [Credential] = credentials.map { credential in
            guard let outcome = statuses[credential.id] else { return credential }
            switch outcome {
            case .success(let status):
                statusListCache[credential.id] = status
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
        // 이미지 판정은 W3C 데이터 모델의 claim.type 기준 — 디코드 실패 시 원문 텍스트(ImageClaim 참조).
        let claims: [ClaimEntry] = vc.credentialSubject.claims.map { claim in
            ClaimEntry(kind: .row(
                label: claim.caption,
                value: ImageClaim.claimValue(type: claim.type, encoded: claim.value)
            ))
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
    /// 메타는 issuer-signed JWT payload(iat/exp)에서, 클레임은 SDK `consentItems` 에서 뽑는다.
    /// 여기서의 상태는 **만료일 기준**이며, 유효한 카드의 폐기·정지 여부는 호출측이 Status List 로
    /// 판정해 덮어쓴다.
    ///
    /// 클레임을 못 읽으면(`consentItems` throw — issuer JWT payload 손상) **nil 을 돌려 목록에서
    /// 뺀다**(결정 2026-08-12). 클레임 없는 빈 카드를 정상인 것처럼 세워 두지 않는다.
    private static func makeSDJWTCredential(_ issued: SdJwtCredentialItem,
                                            payload: [String: Any]) -> Credential? {
        // 클레임 구성은 VP 제출 동의화면과 **같은 근거·같은 규칙**이다 — SdJwtClaimDisplay 참조.
        // 값이 복합(object/array)이거나 하위 claim 이 있으면 접이식 .group, 아니면 단일 .row.
        guard let consentItems = try? issued.consentItems else { return nil }
        let claims: [ClaimEntry] = SdJwtClaimDisplay.consentRows(consentItems).map { row in
            let items = row.nested.map {
                ClaimItem(label: $0.claimName, value: SdJwtClaimDisplay.value(of: $0))
            } + row.rideAlong.map {
                // 하위 항목도 이미지일 수 있다 — 판정은 상위와 같은 이름 화이트리스트.
                ClaimItem(label: $0.label,
                          value: ImageClaim.claimValue(name: $0.label, text: $0.value))
            }
            guard items.isEmpty else {
                return ClaimEntry(kind: .group(title: row.item.claimName, items: items))
            }
            return ClaimEntry(kind: .row(label: row.item.claimName,
                                         value: SdJwtClaimDisplay.value(of: row.item)))
        }

        // exp 가 지났으면 expired — 이 경우 Status List 는 조회하지 않는다.
        let isExpired = epochDate(payload["exp"]).map { $0 < Date() } ?? false

        return Credential(
            id: issued.id,
            // 제목 규칙은 VP 제출 카드와 공유 — SdJwtClaimDisplay 참조.
            name: SdJwtClaimDisplay.title(of: issued),
            badge: .sdJwt,
            // 발급자는 payload 의 `iss` 가 아니라 SDK `issuerDid`(발급 JWT 헤더 `kid`)다 —
            // 둘 다 서명이 덮지만 `iss` 는 발급자가 자기에 대해 적은 값이고, `kid` 는 발급 시
            // 서명을 실제로 검증한 키다. 어긋나면 검증이 붙어 있는 쪽을 쓴다(규칙은 mDoc 과 공유).
            issuer: issued.issuerDid ?? Self.unknownIssuer,
            issued: epochDisplay(payload["iat"]),
            valid: epochDisplay(payload["exp"]),
            status: isExpired ? .expired : .active,
            claims: claims
        )
    }

    // MARK: - MdocCredentialItem → Credential 매핑

    /// 저장된 mDoc 한 건을 표시용 `Credential` 로 변환.
    ///
    /// 메타는 MSO 의 `validityInfo` 에서 온다 — ISSUED 는 `validFrom`, VALID UNTIL 은 `validUntil`.
    /// 발급자는 SDK `issuerDid`(`issuerAuth` 의 `kid`)다 — 발급 시 그 DID 로 서명을 검증했으므로
    /// 근거가 있는 값이다. `docType` 은 문서 **종류**라 "Issued by" 자리에 맞지 않고,
    /// 원소의 `issuing_authority` 는 홀더가 발급 폼에 입력한 값이 실려 오므로 신원 근거가 못 된다.
    ///
    /// 여기서 정하는 상태는 **만료일 기준까지**다 — MSO 에 `status.status_list` 가 있으면 호출측
    /// (`oid4vcDisplayCredentials`)이 Status List 를 조회해 폐기·정지로 덮는다. 참조가 없는 발급물은
    /// 만료일 판정에서 끝난다(표준상 optional 이라 없을 수 있다).
    private static func makeMdocCredential(_ item: MdocCredentialItem) -> Credential {
        let validity = item.mdoc.validityInfo
        return Credential(
            id: item.id,
            // 제목 규칙은 SD-JWT 와 공유 — MdocClaimDisplay 참조.
            name: MdocClaimDisplay.title(of: item),
            badge: .mDoc,
            issuer: item.issuerDid ?? Self.unknownIssuer,
            issued: dateFormatter.string(from: validity.validFrom),
            valid: dateFormatter.string(from: validity.validUntil),
            status: validity.validUntil < Date() ? .expired : .active,
            claims: mdocClaims(item.consentItems)
        )
    }

    /// mDoc 원소 → 상세화면 클레임 목록.
    ///
    /// 순회 대상은 `consentItems` 다 — `Mdoc.namespaces` 는 `Dictionary` 라 순회 순서가 실행마다
    /// 달라져 화면을 열 때마다 항목이 재배열된다. `consentItems` 는 발급자가 서명한 원소 순서
    /// (네임스페이스는 이름순)를 SDK 가 고정해 준다.
    ///
    /// **네임스페이스로 묶지 않고 평면으로 그린다** — 라벨은 `elementIdentifier` 원문 그대로다
    /// (VP 화면과 같은 규칙). 원소 이름에 네임스페이스가 이미 들어 있어 접두하지 않는다.
    /// 값이 비어 있는 원소도 거르지 않고 그대로 싣는다 (결정 2026-08-11).
    private static func mdocClaims(_ items: [MdocConsentItem]) -> [ClaimEntry] {
        items.map { mdocEntry($0) }
    }

    /// 한 원소 — 복합값(array/map)은 접이식 그룹으로 펼친다.
    private static func mdocEntry(_ item: MdocConsentItem) -> ClaimEntry {
        let children = MdocClaimDisplay.childRows(item.value)
        let label = item.elementIdentifier
        guard !children.isEmpty else {
            return ClaimEntry(kind: .row(
                label: label,
                value: MdocClaimDisplay.claimValue(name: item.elementIdentifier, value: item.value)
            ))
        }
        return ClaimEntry(kind: .group(
            title: label,
            items: children.map { ClaimItem(label: $0.label, value: $0.value) }
        ))
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
