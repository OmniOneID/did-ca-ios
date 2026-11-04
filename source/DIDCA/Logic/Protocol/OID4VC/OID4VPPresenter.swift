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
    /// No credential can be submitted for the request — in the display step, the matched credentialId's actual credential
    /// could not be found in storage so no card came out; in the submit step, the wallet is empty or no credential
    /// remains after applying consent.
    /// The latter cannot be reached via the UI on the DCQL path — there is always at least one lock, so a card cannot be
    /// emptied (see "Disclosure scope" below). Kept only as a safety net against false success.
    case noEligibleCredentials
    /// The QR payload has no `request_uri` query, or it does not parse as a URL.
    case invalidRequestURI
    /// `request_uri` GET is not 200 (could not receive the authorization request JWS).
    case failedToFetchJWS
    /// The `request_uri` response body is not a UTF-8 string (not a compact JWS at all).
    /// 3-part violations, base64url errors and a missing header JWK are thrown by SDK `JWS` as its own errors.
    case malformedJWS
    /// Authorization request JWS signature verification failed.
    case failedToVerifyJWS
    /// vp_token submission got a non-2xx response. Carries the HTTP status code.
    case failedToSubmit(Int)
}

// MARK: - OID4VP presentation flow (SDK `WalletAPI` + ported `OID4VPProtocol` API)
//
// Parallel in structure to the regular VP (`VerifyVcProtocol`). The differences: (1) payload entry is an
// `openid4vp://...?request_uri=` authorization request instead of verifier request-profile, (2) matching is a
// DCQL query (`WalletAPI.matchCredentials`) instead of the submission profile schema, and (3) submission is an
// authorization response (vp_token) instead of request-verify.
//
// Submission is a single SDK path regardless of format — the request's `format` decides which store to read (SDK),
// createVpToken assembles the vp_token with a per-format presenter (SD-JWT = KB-JWT string, W3C = ldp_vp object),
// and it even builds the transmittable form body (plaintext / JWE-sealed for direct_post.jwt). submitVpToken just
// POSTs that body to `response_uri`. The app knows neither the format nor that storage is split in two.
//
// Submission set = verifier request (DCQL match) ∩ user consent (selection). It is the intersection of both constraints
// and exceeds neither — consent is finalized by `VPRequestView` as the selection and passed in (not the deselection).
//
// Step mapping ([1] and the latter half of [5] are app implementations ported from SDK OID4VPProtocol; the rest are SDK calls):
//   [1] getAuthorizationRequest(uri:)                  request_uri GET → JWS verify → AuthorizationRequest
//   [2] TokenGenerator.requestWalletToken              .LIST_VC_AND_PRESENT_VP wallet token
//   [3] WalletAPI.matchCredentials                     format → choose store → DCQL match
//                                                      → [MatchedCredential] (DCQL declaration order)
//   [4] (app UI) user consent + PIN/BIO auth → applyConsent narrows the match result
//   [5] WalletAPI.createVpToken → submitVpToken        SDK assembles, signs, seals; app only POSTs (common to both formats)
//
// Display (presentationSummary) and submission (submit) match on the same basis — both decide the submission target
// through the single SDK entry point `matchCredentials(hWalletToken:authRequest:)`. The actual credential is
// never used for matching, only for rendering values on the card (since MatchedCredential carries no values).
// Hence the cards on screen always equal the submission target, and a match failure propagates as a display failure, not a missing card.
//
// Disclosure scope — all three formats follow the same rules:
//  - Exposure is always **the whole credential** (W3C = all claims / SD-JWT·mDoc = all SDK consentItems).
//    DCQL has no "what to show" axis like OpenDID submission profile's `displayClaims`.
//  - Locks (required) are exactly the SDK-returned `MatchedCredential.claimCodes`. Even if the verifier does not
//    specify `claims`, the SDK fills in every claim (agreed contract), so the app never needs to inspect DCQL.
//    Unspecified query = every item locked = full forced disclosure.
//  - Locks cannot be turned off and are checked from entry. Combined with the contract that `claimCodes` never
//    comes back empty, **a card cannot be emptied via the UI** — there is always at least one lock.
//  - Submission is `claimCodes ∪ checked` per query. The union is also an SDK contract — the selection **cannot
//    narrow** the claimCodes given by matching (narrowing makes the SDK reject with invalidSelectedCredentials), and
//    codes beyond it pass through, disclosing those claims too. Required codes dropped from the screen (plaintext claims)
//    also remain in the submission via this union.
nonisolated enum OID4VPPresenter {

    /// Data for the VP request screen — issue wallet token → **match via the same SDK entry point as submit** →
    /// read the matched credentialId's actual credential from storage and render its values on the card.
    ///
    /// The single basis for matching is `WalletAPI.matchCredentials(hWalletToken:authRequest:)` (same as submit).
    /// If no VC matches, the SDK throws `noMatchedCredentials` (06502) (cannot present), and
    /// since this throw is not swallowed, the cards on screen always equal the submission target (consent integrity).
    /// Fetching the actual credential is for value rendering only, not matching — MatchedCredential carries no values.
    static func presentationSummary(authRequest: AuthorizationRequest) async throws -> VpPresentationSummary {
        // Matching and rendering use the same token — .LIST_VC_AND_PRESENT_VP also includes store read permission.
        let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .LIST_VC_AND_PRESENT_VP)

        // [Authoritative] Submission-target matching — same entry point as submit. The SDK looks at the request format to pick
        // the store and match (requests are single-format; throws if mixed/missing), noMatchedCredentials if the match is empty.
        //
        // "Does not hold the requested credential at all" is not an error but a **notice case** (the "no submittable credential" notice) —
        // since we decided not to distinguish it from zero ACTIVE by message, convert it to the same thing and throw here.
        let matched: [MatchedCredential]
        do {
            matched = try WalletAPI.shared.matchCredentials(
                hWalletToken: hWalletToken,
                authRequest: authRequest
            )
        } catch let error as WalletCoreError where Self.meansNothingToSubmit(error) {
            throw NoSubmittableCredentialError()
        }

        // Cards are per credential — not per query. Merge matches by credential, then render.
        let merged = mergeByCredential(matched)

        // Find the actual credential the match points to and pick the rendering path **by type**.
        //
        // Do not read the request's `format` string. If the app held format tokens (`dc+sd-jwt-did`, etc.), when the
        // SDK changed a token the branch would silently fall to default and produce **a blank screen with no error**.
        // The actual credential itself tells which store it came from and what type it is, so no string is needed.
        // (The matching entry point already chose the store by request format — the credentials here are its result.)
        let documents = try await renderDocuments(merged: merged, hWalletToken: hWalletToken)

        // Matched, but zero ACTIVE or the actual credential wasn't found — grouped with the same notice as not-held.
        guard !documents.isEmpty else { throw NoSubmittableCredentialError() }

        // Even if cards remain, **if any single query lost all its candidates** the request cannot be fulfilled.
        try Self.requireEveryQuerySurvives(
            matched: matched,
            surviving: Set(documents.map(\.credentialId)),
            dcqlQuery: authRequest.dcqlQuery
        )

        // OID4VP has no verifier profile — use client_metadata's display name, or client_id if absent.
        let verifierName = authRequest.clientMetadata["client_name"]?.asString ?? authRequest.clientId
        return VpPresentationSummary(verifierName: verifierName, documents: documents)
    }

    /// Match result → cards. Reads each of the two stores once and sends each credential to the mapper for its type.
    /// A credentialId found in neither store is skipped.
    ///
    /// **Only ACTIVE ones become candidates** — Inactive·Expired are excluded from both the single/multiple
    /// decision and the option list. See `CredentialStore.submittableIds` for the decision ladder.
    /// If no card remains, the caller shows the "no submittable credential" notice.
    private static func renderDocuments(
        merged: [(credentialId: String, requiredCodes: Set<String>)],
        hWalletToken: String
    ) async throws -> [VpPresentationDocument] {
        // Don't query an empty store — requests are single-format, so one side is usually empty.
        let w3c = WalletAPI.shared.isAnyCredentialsSaved
            ? ((try WalletAPI.shared.getAllCredentials(hWalletToken: hWalletToken)) ?? [])
            : []
        let oid4vc = WalletAPI.shared.isAnyOID4VCSaved
            ? try WalletAPI.shared.getAllOID4VCs(hWalletToken: hWalletToken)
            : []

        // Decide ACTIVE **first, all at once**, before building cards — candidates usually point to the same Status List,
        // so asking one by one fetches the same token once per candidate, and if only some of those fail, candidates
        // based on the same list end up with different verdicts (see `CredentialStore.submittableIds`).
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
                // For W3C the lookup target is the server's `vc-meta`, a per-VC API — no way to batch, so ask one by one.
                guard let vc = w3c.first(where: { $0.id == entry.credentialId }) else { continue }
                guard await CredentialStore.shared.isSubmittable(w3c: vc) else { continue }
                documents.append(await w3cDocument(vc, requiredCodes: entry.requiredCodes))
            }
        }
        return documents
    }

    /// Checks whether the ACTIVE filter removed **all candidates of any single query** — if so, stop at the display step.
    ///
    /// `renderDocuments` drops Inactive·Expired from the cards, but matching at the submit step doesn't know
    /// that filter. So when query A has an active credential and query B's only candidate is revoked, a card
    /// remains, the consent screen opens, and after the user completes auth the SDK rejects the submission
    /// (`invalidSelectedCredentials` — every matched query must be included in the selection). An unfulfillable request
    /// should go to **the same notice as not-held** (`NoSubmittableCredentialError`), not a failure popup, and must end before auth.
    ///
    /// With `credential_sets`, the request may still be fulfilled by another combination even if one query is empty. That
    /// satisfaction check is owned by the SDK's authoritative `requireCredentialSetsSatisfied`, so the app doesn't keep a
    /// second implementation — in that case it gives up the check and keeps the existing behavior (show remaining cards).
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

    /// SDK match failures that should read as **"nothing to submit"** — the "no submittable credential" notice, not an error popup.
    ///   · 06502 `noMatchedCredentials`      — holds no credential matching the request
    ///   · 06503 `credentialSetsNotSatisfied` — held credentials cannot fill the requested combination
    /// Other match errors (unsupported format, malformed DCQL, etc.) are real errors and are propagated as-is.
    private static func meansNothingToSubmit(_ error: WalletCoreError) -> Bool {
        error.code == "MSDKWLT06502" || error.code == "MSDKWLT06503"
    }

    /// Merges match results per credential — one card = one credential.
    ///
    /// One credential can match several queries, but since exposure is the whole credential regardless of query,
    /// only the required set differs per query. Merging by union loses nothing — keeping only the earlier match and
    /// dropping the later one would make the required claims of the later query vanish from the screen entirely.
    /// Order is the order the SDK gave (DCQL declaration order — deterministic).
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

    /// One W3C VC card — exposure is all VC claims, REQUIRED is the codes the match pointed to.
    private static func w3cDocument(
        _ vc: VerifiableCredential,
        requiredCodes: Set<String>
    ) async -> VpPresentationDocument {
        let claims = vc.credentialSubject.claims.map { claim in
            VpPresentationClaim(
                code: claim.code,
                label: claim.caption,
                // Image claims (portrait, etc.) are drawn as images instead of value text.
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
            bindingKeyId: nil           // For W3C the signing key isn't fixed; it depends on whether a passcode is given.
        )
    }

    /// One SD-JWT card.
    ///
    /// Rows are based on SDK `consentItems`. **The app does not build claim codes** — the side that builds codes and
    /// the side that interprets them at submission are bound together inside the SDK, so if the app walked disclosures
    /// itself to compose names, it would be a second implementation of the same rule and any divergence becomes a submission failure.
    /// Nesting, plaintext-ness, and whether one code points to two claims are also decided by that walk (SDK doc §4).
    ///
    /// Exposure is **all held claims**. Drawing only what the match pointed to would leave the user no way to voluntarily
    /// disclose items the verifier didn't ask for, and the screen would just mirror the request scope.
    /// Locks are the codes the match pointed to — DCQL is not re-read for that decision.
    private static func sdjwtDocument(
        _ cred: SdJwtCredentialItem,
        requiredCodes: Set<String>
    ) throws -> VpPresentationDocument {
        // consentItems parses the issuer JWT payload on the spot — throws 06102 if it can't be read.
        // Not swallowed: submitting without having drawn the card would be disclosure without consent.
        let claims = Self.sdjwtClaims(try cred.sdjwt.consentItems(), requiredCodes: requiredCodes)
        return VpPresentationDocument(
            credentialId: cred.id,
            // Title rules are shared with the list/detail — see SdJwtClaimDisplay.
            title: SdJwtClaimDisplay.title(of: cred),
            claims: claims,
            // If a parent is REQUIRED its child codes must go too — collect again from the tree to include children.
            requiredCodes: Self.requiredCodes(in: claims),
            // Key bound at issuance — this value decides the presentation auth method (not user-selectable).
            bindingKeyId: cred.kid
        )
    }

    /// `consentItems` → screen rows. Items to filter out, nesting decisions and order follow **the same rules** as the detail screen
    /// (`SdJwtClaimDisplay.consentRows`). Here we only add whether each is REQUIRED on top of that result.
    ///
    /// **Nesting moves as a whole** — one parent checkbox toggles the entire subtree, and children have
    /// no individual checkboxes. A child's `code` is used only when building the submission set.
    ///
    /// Required-ness **only comes from the parent and propagates down** — if a parent is REQUIRED its entire subtree is
    /// REQUIRED. (The server never sends a combination where only a child is REQUIRED.)
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
                // A group (composite value) has an empty value slot — the values are drawn by the child rows.
                value: children.isEmpty ? SdJwtClaimDisplay.value(of: row.item) : .text(""),
                required: required,
                children: children
            )
        }
    }

    /// One mDoc card — uses the same basis (`consentItems`) as SD-JWT. The code is a value built by the SDK, and
    /// the app uses `namespace`·`element name` only to draw on screen (it does not assemble codes from the two).
    ///
    /// Exposure is all held elements, REQUIRED is the codes the match pointed to. Elements with empty values are not filtered
    /// either — even while the issuer server sends empty values, what goes out stays visible as-is.
    private static func mdocDocument(
        _ cred: MdocCredentialItem,
        requiredCodes: Set<String>
    ) -> VpPresentationDocument {
        let claims = Self.mdocClaims(cred.mdoc.consentItems, requiredCodes: requiredCodes)
        return VpPresentationDocument(
            credentialId: cred.id,
            // Title rules are shared with the list/detail — see MdocClaimDisplay.
            title: MdocClaimDisplay.title(of: cred),
            claims: claims,
            requiredCodes: Self.requiredCodes(in: claims),
            // Key bound at issuance — like SD-JWT, this value decides the presentation auth method.
            bindingKeyId: cred.kid
        )
    }

    /// mDoc `consentItems` → screen rows.
    ///
    /// Drop `isAmbiguous` — one code points to two elements and the SDK fails it at submission, so
    /// don't collect consent we can't honor. Order follows the issuer-signed order set by `consentItems` as-is
    /// (iterating `Mdoc.namespaces` directly reorders items every time the screen opens).
    ///
    /// **Draw flat, not grouped by namespace.** A namespace is not an indivisible bundle but
    /// merely a name space (the unit of selective disclosure is one element = one digest), and the REQUIRED/OPTIONAL sections
    /// cut across those bundles. Labels use the raw `elementIdentifier` — the element names the issuer
    /// sends already contain the namespace, so prefixing it would show it twice.
    private static func mdocClaims(_ items: [MdocConsentItem],
                                   requiredCodes: Set<String>) -> [VpPresentationClaim] {
        items.filter { !$0.isAmbiguous }
            .map { Self.mdocClaim($0, requiredCodes: requiredCodes) }
    }

    /// One element — composite values (array/map) expand into a collapsible group. Children are inside a single element's value
    /// and cannot be split out (digests are per element) → display only (`code == nil`).
    /// Proximity presentation (`ProximityPresenter`) draws the same rows too — mDoc element display rules live in one place.
    static func mdocClaim(_ item: MdocConsentItem,
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

    /// Collects the **always-submitted codes** from the exposure tree — REQUIRED rows and everything under them.
    /// If a parent is REQUIRED its children come down REQUIRED too (propagation), so this one traversal also gathers child codes.
    private static func requiredCodes(in claims: [VpPresentationClaim]) -> Set<String> {
        var codes: Set<String> = []
        for claim in claims {
            if claim.required, let code = claim.code { codes.insert(code) }
            codes.formUnion(requiredCodes(in: claim.children))
        }
        return codes
    }

    /// Build + submit the VP. Matching, assembly and transport are all a single SDK path — the app doesn't know the format.
    ///
    /// **Which credentials to submit is decided by the request.** The SDK entry point looks at `dcql_query.credentials[].format`
    /// and reads the corresponding store (W3C = `getAllCredentials` / SD-JWT = `getAllOID4VCs`). The former approach of the app
    /// searching both stores and picking one let the wallet's holdings decide the submission target, so the screen (summary) and
    /// the submission could diverge.
    /// If there is no submission target at all, abort with `OID4VPPresenterError.noEligibleCredentials` (prevents false success).
    /// passcode is the input value for PIN auth, nil for BIO (the SDK triggers biometrics at signing time).
    ///
    /// ⚠️ Limitation: if one request asks for two formats together, the SDK matching entry point rejects it
    /// (`unsupportedPresentationFormat`). The transport layer could carry a mix, but matching evaluates `credential_sets`
    /// satisfaction per call; resolving that is the SDK's job. The same exception occurs when the request has no `format` —
    /// it's mandatory per spec, so the app does not guess a fallback.
    /// - parameter selectedCodes: credentialId → claim (disclosure) names the user consented to disclose.
    ///   The submission set is `verifier request (match result) ∩ user consent` — format-agnostic, so
    ///   this path stays the same even if DCQL claim queries are added for W3C (lock state is decided by the display mapper).
    static func submit(authRequest: AuthorizationRequest,
                       passcode: String?,
                       selectedCodes: [String: Set<String>] = [:]) async throws {
        guard WalletAPI.shared.isAnyCredentialsSaved || WalletAPI.shared.isAnyOID4VCSaved else {
            throw OID4VPPresenterError.noEligibleCredentials
        }

        // Matching and submission use the same token — .LIST_VC_AND_PRESENT_VP also includes store read permission.
        let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .LIST_VC_AND_PRESENT_VP)
        let matched = try WalletAPI.shared.matchCredentials(
            hWalletToken: hWalletToken,
            authRequest: authRequest
        )
        // If nothing remains after applying consent, abort instead of a false success (safety net unreachable from the current UI).
        let consented = Self.applyConsent(matched, selectedCodes: selectedCodes)
        guard !consented.isEmpty else {
            throw OID4VPPresenterError.noEligibleCredentials
        }

        // The SDK resolves the signing key (SD-JWT = kid bound at issuance, W3C = whether a passcode is present) — the app
        // passes only hWalletToken/passcode. createVpToken assembles the vp_token with a per-format presenter
        // (SD-JWT = KB-JWT string, W3C = ldp_vp object + client_id/nonce binding) and builds the authorization response
        // form body too — if response_mode is direct_post.jwt, JWE sealing is also done here.
        // submitVpToken just POSTs that body to response_uri (failedToSubmit on non-2xx).
        let vpToken = try WalletAPI.shared.createVpToken(
            hWalletToken: hWalletToken,
            authRequest: authRequest,
            matchedCredentials: consented,
            passcode: passcode
        )
        try await Self.submitVpToken(authRequest: authRequest, vpToken: vpToken)
    }

    /// Applies the user's checks to the match result — **submission = required per query ∪ checked**.
    ///
    /// Since exposure is the whole credential and locks can't be turned off, the checked set already contains the required ones. Still,
    /// keeping it a union is the SDK contract — omitting even one claimCode given by matching gets the submission rejected
    /// (`invalidSelectedCredentials`). Required codes that couldn't be drawn, like plaintext claims dropped from the screen, are
    /// revived here. Required ones are what the verifier asked for, so this is not over-disclosure either.
    ///
    /// - At least one check: `claimCodes ∪ checked` — the DCQL path always comes this way.
    /// - Empty check set: drop that credential. **This branch is unreachable from the current UI** — there is
    ///   always at least one lock, so a card can't be emptied entirely. It's kept anyway because passing an empty claimCodes
    ///   as-is would make the SDK read it as "disclose everything", the exact opposite (blocks full disclosure without consent).
    ///   If a per-credential reject UI is added, this branch becomes a normal path.
    /// - Key absent from the map entirely: a credential not on screen — leave the match result as-is.
    ///   (Documents shown on screen arrive as an empty set even with no checks, so they never come this way.)
    private static func applyConsent(
        _ matched: [MatchedCredential],
        selectedCodes: [String: Set<String>]
    ) -> [MatchedCredential] {
        matched.compactMap { mc in
            // The screen sends **only the one selected candidate** — a missing key means a candidate the user didn't pick.
            // (Previously it was treated as "not on screen" and passed through, but once screens with multiple candidates appeared,
            //  unpicked cards would have gone out too.)
            guard let checked = selectedCodes[mc.credentialId] else { return nil }
            // Even with zero checks, submit if there are REQUIRED codes (`claimCodes`) — OPTIONAL defaults to off, so
            // "zero checks" does not mean "don't submit".
            let codes = checked.union(mc.claimCodes)
            guard !codes.isEmpty else { return nil }
            return MatchedCredential(queryId: mc.queryId,
                                     credentialId: mc.credentialId,
                                     claimCodes: Array(codes))
        }
    }

}

// MARK: - Ported SDK OID4VPProtocol API (static · same names/signatures · stateless)
//
// Ported for the same reasons and in the same way as OID4VCI (`IssueOID4VcProtocol`). Both APIs are thin layers that
// make one HTTP call with information the app holds (authorization request URI / fully assembled form body) and validate
// the result, so there's no reason to tie them to the SDK surface. The core (issuance, signing, sealing) remains the SDK's job.
//
// JWS parsing and ES256 verification use the SDK's authoritative `JWS` as-is (same code as SD-JWT handling). The verification key
// comes from the verifier DID Document pointed to by the header `kid`, so not just signature integrity but **signer identity**
// is verified — identity holds only when the basis lies outside the request (the DID registry) (`JWSSignerVerifier`).
extension OID4VPPresenter {

    /// Receive and parse the authorization request — `request_uri` GET → JWS signature verification → `AuthorizationRequest`.
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

        // The signing key comes **not from the header `jwk`** but from the verifier DID Document pointed to by `kid`.
        // `jwk` is a key the requester inserted itself, so it only tells us "not tampered with" — verifying with it would let
        // anyone sign with their own key, write any institution name into `client_id`·`client_name`, and obtain consent.
        // Those values show up as-is in "Requesting Institution" on the presentation screen.
        // Same verification path as Status List tokens (`JWSSignerVerifier`).
        guard let kid = try jws.protectedHeader.kid else {
            throw OID4VPPresenterError.malformedJWS
        }
        try await JWSSignerVerifier.verify(jws: jws, kid: kid)

        // The payload is snake_case — the Jsonable default decoder sees FromSnake and converts it.
        // (SDK `getPayload()` is internal, so payloadData is decoded directly.)
        return try AuthorizationRequest(from: jws.payloadData)
    }

    /// POSTs the authorization response body built by `createVpToken` to the verifier's `response_uri` as
    /// `application/x-www-form-urlencoded`. Body assembly, signing and JWE sealing are already done.
    /// - Returns: the verifier response body and HTTP status code.
    /// - Throws: on non-2xx, `AppError.server` carrying the failure reason the verifier gave; if that format can't be read,
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
            // The status code alone doesn't tell what was rejected — preserve the failure reason the verifier wrote in the body
            // and throw it (`{error, errorDescription}`). Falls back to the status code if the format can't be read.
            if let serverError = AppError.server(from: data) {
                throw serverError
            }
            throw OID4VPPresenterError.failedToSubmit(statusCode)
        }
        return (data, statusCode)
    }
}
