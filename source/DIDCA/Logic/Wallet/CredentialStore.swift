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

// In-memory cache of issued/fetched VCs and their extra info (VCSchema, status).
// - credentials:    result of WalletAPI.getAllCredentials (SDK model). Reused without refetching.
// - zkpCredentials: result of WalletAPI.getAllZKPCredentials. Paired with VCs, so loaded together
//                   (ZKP exists only on top of a held VC — there is no ZKP-only case).
// - schemaCache:    credentialSchema.id(URL) → VCSchema. Saves the cost of repeated title lookups.
// - statusCache:    vcId → VCStatusEnum. Saves the cost of repeated vc-meta lookups.
// - zkpSchemaCache: ZKPCredential.schemaId → ZKPCredentialSchema. For mapping ZKP claim labels (caption).
@Observable
final class CredentialStore {

    static let shared = CredentialStore()
    private init() {}

    private(set) var credentials: [VerifiableCredential] = []
    private(set) var zkpCredentials: [ZKPCredential] = []
    /// Holdings issued via OID4VCI (SD-JWT and mDoc arrive mixed in one list). Stored separately from W3C, so
    /// read separately, but the read happens in one place, `reloadCredentials()` — if the list draws the two stores
    /// from snapshots taken at different times, a newly issued card shows up one beat late.
    /// ⚠️ OID4VP matching does not use this cache — presentation targets are read fresh on the spot.
    private(set) var oid4vcCredentials: [any CredentialItem] = []

    @ObservationIgnored private var schemaCache: [String: VCSchema] = [:]
    @ObservationIgnored private var statusCache: [String: VCStatusEnum] = [:]
    @ObservationIgnored private var zkpSchemaCache: [String: ZKPCredentialSchema] = [:]
    // Status List status (shared by SD-JWT·mDoc) — same cadence as the W3C `statusCache` (cache first on main entry,
    // forced refetch on detail entry). Neither the raw Status List Token nor the decompressed status array is kept
    // — only the single resulting enum.
    @ObservationIgnored private var statusListCache: [String: StatusListStatus] = [:]
    // credentialId → Status List location. Refetching on detail entry needs uri·idx, and those values
    // only come from the stored credential, so they are kept alongside during list loading.
    @ObservationIgnored private var statusListRefs: [String: StatusListVerifier.Reference] = [:]

    /// Clears the status caches — makes the next list load re-query Status List / vc-meta.
    /// Status can change on the server at any time (revocation, suspension), so the first value must not be held for the app's whole lifetime.
    /// Called on return from background. `statusListRefs` (uri·idx) are fixed per credential, so they are kept.
    func invalidateStatusCache() {
        statusCache.removeAll()
        statusListCache.removeAll()
    }

    /// Re-reads all wallet holdings into memory — W3C VC + ZKP + OID4VC (SD-JWT·mDoc).
    /// The storage is split in two, but one token suffices (`.LIST_VC` permits reading both),
    /// and reading them together makes the list a snapshot of a single point in time.
    ///
    /// OID4VC read failures are swallowed — an empty or unreadable store on that side is no reason for the W3C
    /// list to vanish too (and vice versa: a W3C read failure is absorbed by the caller as an empty list).
    func reloadCredentials() async throws {
        guard WalletAPI.shared.isAnyCredentialsSaved || WalletAPI.shared.isAnyOID4VCSaved else {
            credentials = []
            zkpCredentials = []
            oid4vcCredentials = []
            OID4VcIssuerStore.prune(keeping: [])
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

        // Issuer reference cleanup runs **only when the wallet was read correctly** — reading an empty list caused by a
        // read failure as "everything was deleted" would wipe issuer records of intact credentials, blocking server revocation.
        if WalletAPI.shared.isAnyOID4VCSaved {
            if let items = try? WalletAPI.shared.getAllOID4VCs(hWalletToken: hWalletToken) {
                oid4vcCredentials = items
                OID4VcIssuerStore.prune(keeping: Set(items.map(\.id)))
            } else {
                oid4vcCredentials = []
            }
        } else {
            oid4vcCredentials = []
            OID4VcIssuerStore.prune(keeping: [])
        }
    }

    /// Looks up VCSchema by schema id(URL) — from cache if present, otherwise GET and cache.
    func schema(id: String) async throws -> VCSchema {
        if let cached = schemaCache[id] {
            return cached
        }
        let schema: VCSchema = try await HttpClient.sendGetRequest(urlString: id)
        schemaCache[id] = schema
        return schema
    }

    /// Looks up ZKPCredentialSchema by ZKPCredential.schemaId — cache first, otherwise GET and cache.
    /// Used to turn ZKP claim keys (`namespace.id.label`) into human-readable captions.
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

    /// Looks up the issuance status (ACTIVE/INACTIVE/REVOKED) of a vcId.
    /// Cache first by default; with `forceRefresh`, ignores the cache and queries vc-meta fresh
    /// (used when the current server status matters, e.g. revocation). Either way, the result is written to the cache.
    /// The response's vcMeta is multibase-encoded, so it is decoded and deserialized into VCMeta.
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

    /// Called on detail screen entry — queries the credential's status fresh and converts it to a display status.
    /// Expiry is fixed at issuance, so the existing display value is followed.
    /// On lookup failure, shows a notice toast and returns the last status confirmed during this run, or the existing status if none
    /// (same order as SD-JWT·mDoc's `refreshedStatusListStatus`).
    /// SD-JWT·mDoc are judged by Status List, not by server vc-meta.
    func refreshedStatus(for credential: Credential) async -> CredentialStatus {
        // SD-JWT·mDoc are judged by Status List, not vc-meta — only cards with a reference are queried.
        if credential.badge == .sdJwt || credential.badge == .mDoc {
            return await refreshedStatusListStatus(for: credential)
        }
        let fresh: VCStatusEnum
        do {
            fresh = try await status(forVcId: credential.id, forceRefresh: true)
        } catch {
            // A failed forced lookup does not clear the cache — the remaining value is the last confirmed status.
            OverlayManager.shared.showToast(message: Self.statusCheckFailureMessage)
            guard let cached = statusCache[credential.id] else { return credential.status }
            return Self.detailStatus(cached, current: credential.status)
        }
        return Self.detailStatus(fresh, current: credential.status)
    }

    /// vc-meta status → detail display status. Expiry follows the value decided in the list (`current`).
    private static func detailStatus(_ status: VCStatusEnum,
                                     current: CredentialStatus) -> CredentialStatus {
        switch status {
        case .REVOKED:
            // Revocation is displayed the same as SD-JWT (Status List INVALID).
            return .expired
        case .INACTIVE:
            return .inactive
        case .ACTIVE:
            return current == .expired ? .expired : .active
        }
    }

    /// SD-JWT·mDoc detail entry — expired cards are not queried; otherwise the cache is ignored and Status List
    /// is queried fresh. With no reference (no Status List applied), the expiry-based display is left as is.
    /// On failure, shows a notice toast and keeps the expiry-based display (existing status).
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
            // Don't clear the cache — the fallback for a lookup failure is **the last queried status**,
            // falling back to the expiry-based display only when there is none. Clearing it would lose the fallback on the first failure.
            OverlayManager.shared.showToast(message: Self.statusCheckFailureMessage)
            return statusListCache[credential.id].map(Self.displayStatus) ?? credential.status
        }
    }

    /// Status List status → display status. RESERVED is filtered out as a failure at lookup time.
    private static func displayStatus(_ status: StatusListStatus) -> CredentialStatus {
        switch status {
        case .valid:     return .active
        case .invalid:   return .expired
        case .suspended: return .inactive
        case .reserved:  return .expired
        }
    }

    /// Notice for lookup/verification failure. Says the status was not replaced with "valid" but fell back to the expiry-based display.
    static let statusCheckFailureMessage = "Couldn't check the credential status."

    // MARK: - Presentation candidate decision (PRES-B-06)

    /// Determines **in one go** which credentials can be offered as presentation candidates — returns the set of ids that are ACTIVE.
    /// Inactive·Expired are excluded from both the single/multiple decision and the option list.
    ///
    /// **Candidates are not judged one by one.** Candidates pointing at the same Status List would download the same
    /// token once per candidate; worse than the waste is that the decisions can diverge — if only some fail, candidates
    /// based on the same list get judged at different ladder steps, and the user sees just one of several cards from the
    /// same issuer vanish from the list. The batched lookup is the same path the list display (`oid4vcDisplayCredentials`)
    /// uses.
    ///
    /// The decision ladder has three steps, and **a failure is never promoted to ACTIVE** — steps 2·3 fall back to
    /// already-known facts; they don't count the unknown as valid.
    /// 1. Query the Status List **fresh** (presentation depends on the facts right now, so the cache isn't checked first)
    /// 2. If the lookup or reference read fails, decide by **the last queried status**
    /// 3. If there is none, compare **the expiry date with the current time**
    ///
    /// Unreadable credentials and formats the app can't display are left out of the set (= not candidates).
    func submittableIds(among items: [any CredentialItem]) async -> Set<String> {
        let candidates = items.compactMap(Self.submissionCandidate)

        // [1] Collect only what needs querying — expired ones drop out without a query, and with no reference there's nothing to query.
        var pending: [String: StatusListVerifier.Reference] = [:]
        for candidate in candidates where candidate.expiryStatus != .expired {
            if let reference = candidate.reference {
                pending[candidate.credentialId] = reference
            }
        }
        // [2] Candidates pointing at the same uri fetch the token once and read only per-index bits.
        let statuses = pending.isEmpty
            ? [:]
            : await StatusListVerifier.statuses(for: pending)

        var submittable: Set<String> = []
        for candidate in candidates {
            guard candidate.expiryStatus != .expired else { continue }

            // [3-1] Fresh lookup succeeded — this is the sole basis for the decision.
            if case .success(let status) = statuses[candidate.credentialId] {
                statusListCache[candidate.credentialId] = status
                if Self.displayStatus(status) == .active {
                    submittable.insert(candidate.credentialId)
                }
                continue
            }
            // No Status List applied — no status to check and not expired. (Different from failing to read the reference.)
            if candidate.reference == nil, !candidate.referenceUnreadable {
                submittable.insert(candidate.credentialId)
                continue
            }
            // [3-2] Lookup/reference read failed → last queried status.
            if let cached = statusListCache[candidate.credentialId] {
                if Self.displayStatus(cached) == .active {
                    submittable.insert(candidate.credentialId)
                }
                continue
            }
            // [3-3] No known status → by expiry date.
            if candidate.expiryStatus == .active {
                submittable.insert(candidate.credentialId)
            }
        }
        return submittable
    }

    /// Decision inputs — extracts id, expiry-based status, and Status List reference from the stored item.
    ///
    /// `reference == nil` covers two distinct cases, so they are split via `referenceUnreadable`.
    /// Having no reference at all (no Status List applied) means there is no status to check; failing to read it
    /// means a status that should be checked couldn't be, so it has to go down the fallback ladder.
    private static func submissionCandidate(_ item: any CredentialItem) -> SubmissionCandidate? {
        switch item {
        case let item as SdJwtCredentialItem:
            // Reuse the display mapping as is — the status it produces is exactly step 3 (expiry-based).
            guard let payload = sdJwtPayload(item),
                  let credential = makeSDJWTCredential(item, payload: payload)
            else {
                return nil              // unreadable credentials are not candidates
            }
            var reference: StatusListVerifier.Reference?
            var unreadable = false
            do { reference = try item.sdjwt.status() } catch { unreadable = true }
            return SubmissionCandidate(credentialId: credential.id,
                                       expiryStatus: credential.status,
                                       reference: reference,
                                       referenceUnreadable: unreadable)

        case let item as MdocCredentialItem:
            let credential = makeMdocCredential(item)
            // For mDoc, `Mdoc.parse` has already unpacked the MSO, so reading the reference has no way to fail.
            return SubmissionCandidate(credentialId: credential.id,
                                       expiryStatus: credential.status,
                                       reference: item.mdoc.status,
                                       referenceUnreadable: false)

        default:
            return nil                  // a format the app doesn't know how to display
        }
    }

    private struct SubmissionCandidate {
        let credentialId: String
        let expiryStatus: CredentialStatus
        let reference: StatusListVerifier.Reference?
        let referenceUnreadable: Bool
    }

    /// W3C VC presentation candidate decision — same ladder as above; only the lookup source is `vc-meta`.
    func isSubmittable(w3c vc: VerifiableCredential) async -> Bool {
        guard Self.displayStatus(.ACTIVE, validUntil: vc.validUntil) != .expired else { return false }
        if let fresh = try? await status(forVcId: vc.id, forceRefresh: true) {
            return fresh == .ACTIVE
        }
        if let cached = statusCache[vc.id] {
            return cached == .ACTIVE
        }
        return true                     // not expired, and no known status
    }

    /// Display used when the issuer can't be determined. SDK `issuerDid` is optional, but it is never nil for stored
    /// credentials (issuance verification itself requires that DID) — this is a guard against leaving a blank.
    private static let unknownIssuer = "Unknown"

    /// Re-reads wallet VCs and returns them mapped to display [Credential].
    /// - If the full read (reloadCredentials) fails, returns an empty array — main entry itself is not blocked.
    /// - Per-VC schema lookup failures are absorbed with a name built from the raw data (`fallbackName`).
    /// - Per-VC status lookup failures are not replaced with valid; they fall back to the expiry-based display. The list
    ///   lookup checks the cache first, so a failure here means no status was confirmed during this run.
    /// - The status-check failure toast is shown only once per round, combining W3C and OID4VC.
    func loadCredentials() async -> [Credential] {
        do {
            try await reloadCredentials()
        } catch {
            return []
        }
        // OID4VC (SD-JWT·mDoc) mapping contains Status List lookups and is independent of W3C mapping → start it first
        // so it overlaps with the network round trips of the loop below.
        async let oid4vcDisplay = oid4vcDisplayCredentials()

        var result: [Credential] = []
        var statusCheckFailed = false
        for vc in credentials {
            let zkpCred = zkpCredential(forVcId: vc.id)
            // One VC's schema/status/zkpSchema lookups are independent → start them concurrently to overlap round trips
            // (mitigates up to 3 serial round trips per VC on a cold cache holding up the splash).
            async let vcSchemaTask = schema(id: vc.credentialSchema.id)
            async let vcStatusTask = status(forVcId: vc.id)
            async let zkpSchemaTask = zkpSchemaIfPresent(zkpCred)

            let vcSchema = try? await vcSchemaTask
            let vcStatus = try? await vcStatusTask
            let zkpSchema = await zkpSchemaTask
            // On lookup failure, .ACTIVE is not a "valid" verdict but the value that selects the expiry-based display.
            let credential = Self.makeCredential(
                vc: vc, schema: vcSchema, status: vcStatus ?? .ACTIVE, zkp: zkpCred, zkpSchema: zkpSchema)
            // Expired cards have nothing to report — the toast only fires when before expiry but the status is unknown.
            if vcStatus == nil, credential.status != .expired {
                statusCheckFailed = true
            }
            result.append(credential)
        }
        // OID4VCI credentials are stored separately from W3C, so they are mapped separately and merged.
        let oid4vc = await oid4vcDisplay
        result.append(contentsOf: oid4vc.credentials)
        if statusCheckFailed || oid4vc.statusCheckFailed {
            OverlayManager.shared.showToast(message: Self.statusCheckFailureMessage)
        }
        return result
    }

    /// If there is a ZKP pair, looks up its schema (for claim caption mapping); otherwise nil. Lookup failure is nil too.
    private func zkpSchemaIfPresent(_ zkpCred: ZKPCredential?) async -> ZKPCredentialSchema? {
        guard let zkpCred else { return nil }
        return try? await zkpSchema(id: zkpCred.schemaId)
    }

    /// Maps holdings issued via OID4VCI (SD-JWT·mDoc) to display `[Credential]`.
    /// The store returns both formats in one list, so they are split here and converted by their own rules, **keeping
    /// the stored order** (grouping by format would scramble the issuance order on screen).
    /// Formats the app can't display are silently skipped.
    ///
    /// Status is **expiry first** — if expired, it stays expired and the Status List is not queried.
    /// Only valid cards are queried, and not refetched if cached (same cadence as the W3C `statusCache`).
    /// Lookup/verification failures are not replaced with valid; they fall back to the expiry-based display. Failure is only
    /// returned; the toast is shown by the caller (`loadCredentials`) once per round, combined with W3C failures.
    ///
    /// SD-JWT and mDoc both carry `status.status_list.{uri, idx}` in the same format, and the SDK reads the reference.
    /// **nil and throw are different events** — nil is "no status to check" (no Status List applied),
    /// throw is "reading failed" due to a broken reference. Swallowing the latter as nil would let a revocable card pass
    /// as valid unchecked, so it is escalated with the same treatment as a lookup failure (expiry-based display + toast).
    private func oid4vcDisplayCredentials() async -> (credentials: [Credential], statusCheckFailed: Bool) {
        // [1] Build display data first, collecting only items that need a lookup (not expired + has status reference + not cached).
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
                    reference = try item.sdjwt.status()
                } catch {
                    reference = nil
                    readFailed = true
                }

            case let item as MdocCredentialItem:
                credential = Self.makeMdocCredential(item)
                // For mDoc, `Mdoc.parse` has already unpacked the MSO, so this cannot fail here —
                // a document with a broken reference is caught at parse time and never reaches the list.
                reference = item.mdoc.status

            default:
                continue
            }

            // Expired cards aren't lookup targets to begin with — even if the reference couldn't be read there's nothing to
            // report, so the failure flag isn't set (prevents a toast on every load because of an expired card).
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
            return (credentials, referenceUnreadable)
        }

        // [2] Query all at once — cards pointing at the same list fetch and verify the token only once.
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
                return credential   // keep the expiry-based display
            }
        }
        return (resolved, statusCheckFailed)
    }

    /// The ZKP credential paired with vcId — nil if none.
    /// `ZKPCredential.credentialId` is the same key as `VerifiableCredential.id`.
    func zkpCredential(forVcId vcId: String) -> ZKPCredential? {
        zkpCredentials.first { $0.credentialId == vcId }
    }

    // MARK: - VerifiableCredential → Credential mapping

    private static func makeCredential(vc: VerifiableCredential,
                                       schema: VCSchema?,
                                       status: VCStatusEnum,
                                       zkp zkpCred: ZKPCredential?,
                                       zkpSchema: ZKPCredentialSchema?) -> Credential {
        // VC claims → flat list of .row (VCSchema namespace grouping is follow-up work).
        // Image detection is by claim.type of the W3C data model — on decode failure, raw text (see ImageClaim).
        let claims: [ClaimEntry] = vc.credentialSubject.claims.map { claim in
            ClaimEntry(kind: .row(
                label: claim.caption,
                value: ImageClaim.claimValue(type: claim.type, encoded: claim.value)
            ))
        }
        return Credential(
            id: vc.id,
            name: schema?.title ?? fallbackName(schemaId: vc.credentialSchema.id),
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

    /// Card name when the schema title couldn't be fetched (offline, etc.) — built from the schema URL's `name=` value.
    /// `…/vcschema?name=vc.schema.driver.license` → `Driver License VC`
    /// (strip `vc.schema.` → `.` to spaces → capitalize first letter of each word → append ` VC`).
    /// The schema URL always has `name=`. If it somehow doesn't, the whole URL is converted by the same rule.
    private static func fallbackName(schemaId: String) -> String {
        var name = schemaId
        if let range = schemaId.range(of: "name=") {
            name = String(schemaId[range.upperBound...].prefix { $0 != "&" && $0 != "#" })
        }
        name = name.removingPercentEncoding ?? name
        if name.hasPrefix(vcSchemaNamePrefix) {
            name.removeFirst(vcSchemaNamePrefix.count)
        }
        let words = name.split(separator: ".").map(capitalizeFirst)
        return (words + ["VC"]).joined(separator: " ")
    }

    private static let vcSchemaNamePrefix = "vc.schema."

    /// Uppercase only the first letter — the rest is left as is (`capitalized` lowercases the rest).
    nonisolated private static func capitalizeFirst(_ word: Substring) -> String {
        word.prefix(1).uppercased() + word.dropFirst()
    }

    // MARK: - SdJwtCredentialItem → Credential mapping

    /// The issuer-signed JWT payload of a stored SD-JWT. nil if not SD-JWT format (excluded from display).
    /// Metadata (iss/iat/exp) and the status reference are read from the same payload, so it is parsed only once.
    private static func sdJwtPayload(_ issued: SdJwtCredentialItem) -> [String: Any]? {
        switch issued.format {
        case .sdJwtVc: break
        default: return nil   // msoMdoc/vcdm are excluded from display — Phase 2.
        }
        return (try? SimpleJWTDecoder.parse(issued.sdjwt.credentialJwt))?.payload ?? [:]
    }

    /// Converts one stored SD-JWT into a display `Credential`.
    /// Metadata comes from the issuer-signed JWT payload (iat/exp); claims come from SDK `consentItems`.
    /// The status here is **expiry-based**; for valid cards, the caller judges revocation/suspension via Status List
    /// and overwrites it.
    ///
    /// If the claims can't be read (`consentItems` throws — issuer JWT payload corrupted), **returns nil to drop it from
    /// the list** (decision 2026-08-12). An empty card without claims is not presented as if it were normal.
    private static func makeSDJWTCredential(_ issued: SdJwtCredentialItem,
                                            payload: [String: Any]) -> Credential? {
        // Claim composition uses **the same basis and rules** as the VP presentation consent screen — see SdJwtClaimDisplay.
        // If the value is composite (object/array) or has sub-claims, a collapsible .group; otherwise a single .row.
        guard let consentItems = try? issued.sdjwt.consentItems() else { return nil }
        let claims: [ClaimEntry] = SdJwtClaimDisplay.consentRows(consentItems).map { row in
            let items = row.nested.map {
                ClaimItem(label: $0.claimName, value: SdJwtClaimDisplay.value(of: $0))
            } + row.rideAlong.map {
                // Sub-items can be images too — detection uses the same name whitelist as the parent.
                ClaimItem(label: $0.label,
                          value: ImageClaim.claimValue(name: $0.label, text: $0.value))
            }
            guard items.isEmpty else {
                return ClaimEntry(kind: .group(title: row.item.claimName, items: items))
            }
            return ClaimEntry(kind: .row(label: row.item.claimName,
                                         value: SdJwtClaimDisplay.value(of: row.item)))
        }

        // If exp has passed, expired — in that case the Status List is not queried.
        let isExpired = epochDate(payload["exp"]).map { $0 < Date() } ?? false

        return Credential(
            id: issued.id,
            // Title rules are shared with the VP presentation card — see SdJwtClaimDisplay.
            name: SdJwtClaimDisplay.title(of: issued),
            badge: .sdJwt,
            // The issuer is not the payload's `iss` but SDK `issuerDid` (issuance JWT header `kid`) —
            // both are covered by the signature, but `iss` is what the issuer wrote about itself, while `kid` is the key that
            // actually verified the signature at issuance. If they disagree, use the one backed by verification (rule shared with mDoc).
            issuer: issued.sdjwt.issuerDid ?? Self.unknownIssuer,
            issued: epochDisplay(payload["iat"]),
            valid: epochDisplay(payload["exp"]),
            status: isExpired ? .expired : .active,
            claims: claims
        )
    }

    // MARK: - MdocCredentialItem → Credential mapping

    /// Converts one stored mDoc into a display `Credential`.
    ///
    /// Metadata comes from the MSO's `validityInfo` — ISSUED is `validFrom`, VALID UNTIL is `validUntil`.
    /// The issuer is SDK `issuerDid` (`kid` of `issuerAuth`) — the signature was verified with that DID at issuance,
    /// so the value is well-founded. `docType` is the document **kind**, so it doesn't fit the "Issued by" slot, and
    /// the element `issuing_authority` carries what the holder typed into the issuance form, so it is no basis for identity.
    ///
    /// The status decided here goes **only as far as expiry** — if the MSO has `status.status_list`, the caller
    /// (`oid4vcDisplayCredentials`) queries the Status List and overwrites with revoked/suspended. Credentials without a
    /// reference end at the expiry decision (it's optional in the standard, so it may be absent).
    private static func makeMdocCredential(_ item: MdocCredentialItem) -> Credential {
        let validity = item.mdoc.validityInfo
        return Credential(
            id: item.id,
            // Title rules are shared with SD-JWT — see MdocClaimDisplay.
            name: MdocClaimDisplay.title(of: item),
            badge: .mDoc,
            issuer: item.mdoc.issuerDid ?? Self.unknownIssuer,
            issued: dateFormatter.string(from: validity.validFrom),
            valid: dateFormatter.string(from: validity.validUntil),
            status: validity.validUntil < Date() ? .expired : .active,
            claims: mdocClaims(item.mdoc.consentItems)
        )
    }

    /// mDoc elements → detail screen claim list.
    ///
    /// Iterates over `consentItems` — `Mdoc.namespaces` is a `Dictionary`, so its iteration order varies per run
    /// and items would reshuffle every time the screen opens. `consentItems` has the SDK fix the issuer-signed
    /// element order (namespaces sorted by name).
    ///
    /// **Drawn flat, not grouped by namespace** — labels are the raw `elementIdentifier`
    /// (same rule as the VP screen). Element names already include the namespace, so no prefix is added.
    /// Elements with empty values are not filtered out but included as is (decision 2026-08-11).
    private static func mdocClaims(_ items: [MdocConsentItem]) -> [ClaimEntry] {
        items.map { mdocEntry($0) }
    }

    /// One element — composite values (array/map) expand into a collapsible group.
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

    /// JWT numeric claim (iat/exp, epoch seconds) → Date. nil if not a number.
    private static func epochDate(_ any: Any?) -> Date? {
        guard let number = any as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: number.doubleValue)
    }

    /// epoch seconds → "dd MMM yyyy" (same notation as W3C's displayDate).
    private static func epochDisplay(_ any: Any?) -> String? {
        guard let date = epochDate(any) else { return nil }
        return dateFormatter.string(from: date)
    }

    /// values of the paired ZKP credential → ClaimItem list. Display order is fixed by sorting on key.
    /// Labels are replaced with the schema's caption (`namespace.id.label` → caption); if there's no schema or no match,
    /// a label built from the key (`fallbackZkpLabel`).
    private static func zkpClaimItems(from zkp: ZKPCredential?,
                                      schema: ZKPCredentialSchema?) -> [ClaimItem] {
        guard let zkp else { return [] }
        let captions = schema?.captionMap ?? [:]
        return zkp.values
            .sorted { $0.key < $1.key }
            .map { ClaimItem(label: captions[$0.key] ?? fallbackZkpLabel(key: $0.key),
                             value: .text($0.value.raw)) }
    }

    /// ZKP label when the caption couldn't be fetched (offline, etc.) — the key's last word, first letter uppercased.
    /// `zkp.idcard.name` → `Name`. If the last word is empty (key ending in `.`), the key as is.
    private static func fallbackZkpLabel(key: String) -> String {
        guard let last = key.split(separator: ".", omittingEmptySubsequences: false).last,
              !last.isEmpty
        else { return key }
        return capitalizeFirst(last)
    }

    /// ISO8601 string → "dd MMM yyyy". nil on parse failure.
    private static func displayDate(_ iso: String) -> String? {
        guard let date = isoParser.date(from: iso) else { return nil }
        return dateFormatter.string(from: date)
    }

    /// VC status + expiry date → display status.
    /// REVOKED has no matching case in CredentialStatus, so it is absorbed into .inactive.
    private static func displayStatus(_ status: VCStatusEnum,
                                      validUntil: String) -> CredentialStatus {
        switch status {
        case .REVOKED:
            // Revocation display uses the same badge as SD-JWT (Status List INVALID).
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

    // The single formatter producing the ISSUED / VALID UNTIL notation for the list (MainView) and detail (CredentialHero).
    // Days are zero-padded even when single-digit — so digit widths don't wobble as cards stack vertically.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd MMM yyyy"
        return formatter
    }()
}

// vc-meta response — vcMeta is a multibase-encoded VCMeta string.
private struct VCMetaVO: Jsonable {
    let vcId: String
    let vcMeta: String
}
