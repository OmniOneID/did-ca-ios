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
    /// The wallet holds a VC matching the schema/issuer conditions, but the profile demands, via
    /// `requiredClaims`/`displayClaims`, a claim that VC does not have — a verifier configuration error.
    /// (Holding no VC at all is distinguished as `noMatchingCredential`.)
    case profileClaimMismatch
}

// `AppError.other` builds its message from `"\(error)"` — supply the user-facing sentence here
// so the enum case name is not exposed as-is.
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

// MARK: - Plain VP presentation flow (OpenDID SDK usage example)
//
// The entry point is split into two stages:
//
//   preProcess(offerId:)                   ─ before user authentication
//     [1] request-profile          fetch verifier profile → verifier info / required schemas / txId
//     [2] request-wallet-token     for LIST_VC_AND_PRESENT_VP
//
//   process(claimInfos:passcode:)          ─ right after user PIN/BIO authentication
//     [3] createEncVp + request-verify
//                                   build an encrypted VP from the wallet's VCs and submit it to the verifier
//
// Static entry points are also provided for convenience:
//   VerifyVcProtocol.requestProfile(offerId:)   ─ runs only preProcess, then returns the profile
//   VerifyVcProtocol.presentationSummary(profile:)  ─ output shared by screen and submit (where the rules apply)
//   VerifyVcProtocol.submit(profile:summary:…)      ─ that output + user checks → chains into process
//
// Pattern source: did-ca-ios `VerifyVcProtocol` (CommonProtocol-based singleton).
// DIDCA combines a throwaway instance + static convenience so the caller API
// stays the same as before.
nonisolated final class VerifyVcProtocol {

    // MARK: - State accumulated across stages
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

    // MARK: - Entry point: stages before user authentication (1 ~ 2)
    @discardableResult
    func preProcess(offerId: String) async throws -> _RequestProfile {
        try await requestProfile(offerId: offerId)
        try await requestWalletToken()
        // Safe, since verifyProfile is populated right after requestProfile.
        return verifyProfile!
    }

    // MARK: - Entry point: stage after user authentication (3)
    func process(claimInfos: [ClaimInfo], passcode: String?) async throws {
        try await requestVerify(claimInfos: claimInfos, passcode: passcode)
    }
}

// MARK: - Static convenience
//
// The current UX has two separate user actions — (1) QR scan → fetch profile, then show the VP
// request screen; (2) the user taps submit → authenticate → submit — so the protocol instance is
// not kept between the two stages. Each static method creates a throwaway instance,
// so the walletToken is reissued in the submit stage (negligible cost).
extension VerifyVcProtocol {

    /// VP presentation stage 1 — fetch the verifier profile.
    /// Internally runs preProcess (request-profile + request-wallet-token) and returns only the profile.
    static func requestProfile(offerId: String) async throws -> _RequestProfile {
        let proto = VerifyVcProtocol()
        return try await proto.preProcess(offerId: offerId)
    }

    /// VP presentation stage 2 — apply the user's checks to the submission plan fixed at display time and submit the encrypted VP.
    /// passcode is the entered value for PIN authentication, nil for BIO.
    ///
    /// VC selection, exposure and required-ness are all settled in `presentationSummary` and not redone here —
    /// keeping the same rules in two places lets what the screen showed drift from what is actually sent.
    /// - parameter summary: exactly what `presentationSummary` produced.
    /// - parameter selectedCodes: credentialId → codes the user checked. Every document shown on screen is included
    ///   (an empty set if nothing is checked).
    static func submit(profile: _RequestProfile,
                       summary: VpPresentationSummary,
                       passcode: String?,
                       selectedCodes: [String: Set<String>] = [:]) async throws {
        // Submitted = requiredCodes ∪ checked. Code order is meaningless — SDK `VCManager.makePresentation`
        // walks the VC's claim order and uses this list only for membership.
        let claimInfos: [ClaimInfo] = summary.documents.compactMap { doc in
            // The screen sends **only the one selected candidate** — no key means an unchosen candidate (PRES-B-05).
            guard let checked = selectedCodes[doc.credentialId] else { return nil }
            // Submit even with 0 checks if there are REQUIRED items — OPTIONAL defaults to unchecked, so
            // "0 checks" cannot be read as "send nothing" (a REQUIRED-only setup is the normal path).
            let codes = doc.requiredCodes.union(checked)
            guard !codes.isEmpty else { return nil }
            return ClaimInfo(credentialId: doc.credentialId, claimCodes: Array(codes))
        }
        guard !claimInfos.isEmpty else { throw NoSubmittableCredentialError() }

        let proto = VerifyVcProtocol()
        // The caller already has the preProcess result (profile), so skip [1] and
        // just inject the state into the instance. Only the walletToken is newly issued (re-run [2]).
        proto.verifyProfile = profile
        proto.txId = profile.txId
        try await proto.requestWalletToken()

        try await proto.process(claimInfos: claimInfos, passcode: passcode)
    }

}

// The display models (`VpPresentationSummary` etc.) live in `Logic/Display/PresentationSummary.swift` —
// OID4VP builds the same types and hands them to the same screen, so they don't belong to one protocol.

extension VerifyVcProtocol {

    /// Profile + wallet VCs → output shared by screen and submit. **The single place where submission profile rules are applied.**
    /// One schema is one card, in this order:
    ///
    /// 1. Candidates = `credentialSchema.id` matches && (no `allowedIssuers` or issuer included)
    /// 2. If no schema has any candidate, `noMatchingCredential` — the profile is fine, there is just no card
    /// 3. `presentAll = true` → `displayClaims`/`requiredClaims` are not read.
    ///    Exposed = all VC claims, all locked + all submitted
    /// 4. `presentAll ≠ true` → pick the first candidate that **holds all of** `requiredClaims ∪ displayClaims`.
    ///    If no such VC, `profileClaimMismatch` — a card exists but the profile demanded a claim it lacks
    /// 5. Exposed = `displayClaims ∪ requiredClaims` (all VC claims if neither is set), keeping VC claim order
    /// 6. REQUIRED = exposed ∩ `requiredClaims`. The rest of the exposed set is OPTIONAL (starts unchecked)
    /// 7. Submission is `requiredCodes ∪ checked` in `submit`
    static func presentationSummary(profile: _RequestProfile) async throws -> VpPresentationSummary {
        let verifierName = profile.profile.profile.verifier.name
        let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .LIST_VC_AND_PRESENT_VP)
        let vcs = (try WalletAPI.shared.getAllCredentials(hWalletToken: hWalletToken)) ?? []

        var documents: [VpPresentationDocument] = []
        for schema in profile.profile.profile.filter.credentialSchemas {
            // [1] Narrow down candidates. Skip schemas with no candidates — if none at all, handled together in [2].
            let candidates = vcs.filter { vc in
                vc.credentialSchema.id == schema.id
                    && (schema.allowedIssuers?.contains(vc.issuer.id) ?? true)
            }
            guard !candidates.isEmpty else { continue }

            // [2-1] Only ACTIVE ones become candidates (PRES-B-06) — Inactive/Expired are not submittable.
            // For the decision ladder (fresh lookup → last looked-up status → expiry date) see `CredentialStore.submittableIds`.
            // The lookup source is the server `vc-meta` (a per-VC API), so unlike SD-JWT/mDoc there is no way to batch — ask one at a time.
            var active: [VerifiableCredential] = []
            for candidate in candidates {
                if await CredentialStore.shared.isSubmittable(w3c: candidate) {
                    active.append(candidate)
                }
            }
            guard !active.isEmpty else { continue }

            let vc: VerifiableCredential
            let shownCodes: [String]
            let requiredCodes: Set<String>

            if schema.presentAll ?? false {
                // [3] Full disclosure. The claim list is not read, so a profile mismatch cannot occur.
                vc = active[0]
                shownCodes = vc.credentialSubject.claims.map(\.code)
                requiredCodes = Set(shownCodes)
            } else {
                let required = Set(schema.requiredClaims ?? [])
                // An empty array is treated the same as "not specified" → expose everything.
                let display: Set<String>? = schema.displayClaims.flatMap { $0.isEmpty ? nil : Set($0) }
                // [4] Pick the candidate that has every claim the profile names.
                let needed = required.union(display ?? [])
                guard let matched = active.first(where: { candidate in
                    needed.isSubset(of: Set(candidate.credentialSubject.claims.map(\.code)))
                }) else {
                    throw VerifyVcError.profileClaimMismatch
                }
                vc = matched
                // [5] Exposed = displayClaims ∪ requiredClaims, keeping VC claim order. All if unspecified.
                // Required ones are merged in because of PRES-B-06 — even items the user can't remove must be
                // visible on screen so the user can see what gets submitted. [4] only passes VCs holding all required
                // claims, so caption/value come straight from here.
                let allCodes = vc.credentialSubject.claims.map(\.code)
                let visible = display.map { $0.union(required) }
                shownCodes = visible.map { visible in allCodes.filter(visible.contains) } ?? allCodes
                requiredCodes = required
            }

            let claimsByCode = Dictionary(vc.credentialSubject.claims.map { ($0.code, $0) },
                                          uniquingKeysWith: { first, _ in first })
            // [6] REQUIRED = exposed ∩ required. In [5] the exposed set includes required, so no required item is off screen.
            let claims: [VpPresentationClaim] = shownCodes.compactMap { code in
                guard let claim = claimsByCode[code] else { return nil }
                return VpPresentationClaim(
                    code: code,
                    label: claim.caption,
                    // Image claims (portrait etc.) are drawn as images instead of value text — PRES-B-04.
                    value: ImageClaim.claimValue(type: claim.type, encoded: claim.value),
                    required: requiredCodes.contains(code)
                )
            }
            let title = (try? await CredentialStore.shared.schema(id: schema.id))?.title ?? "Credential"
            documents.append(VpPresentationDocument(
                credentialId: vc.id, title: title, claims: claims,
                requiredCodes: requiredCodes,
                bindingKeyId: nil))   // Plain VP is W3C-only — the signing key depends on whether a passcode is present.
        }
        // [2] No schema had any candidate — not holding one and 0 ACTIVE are not distinguished (PRES-E-04).
        guard !documents.isEmpty else { throw NoSubmittableCredentialError() }
        return VpPresentationSummary(verifierName: verifierName, documents: documents)
    }
}
