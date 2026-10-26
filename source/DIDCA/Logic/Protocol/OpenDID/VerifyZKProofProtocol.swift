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

enum VerifyZKProofError: Error {
    case missingProfile
    /// The candidate referents are empty, or no referent has an ACTIVE sub-referent — blocked before entering the picker.
    case noEligibleZkpCredential
    /// The user hasn't yet picked attribute/predicate values in the picker — every item must be selected at submit time.
    case attributeNotSelected(referentKey: String)
    /// A self-attribute input value is empty.
    case selfAttributeMissing(referentKey: String)
}

// MARK: - ZKP VP presentation flow (OpenDID SDK usage example)
//
// The entry point is split into two stages:
//
//   preProcess(offerId:)                   ─ right after QR scan, just before showing the screen
//     [1] request-proof-request-profile  receive verifier profile (required attr/predicate, nonce)
//     [2] request-wallet-token           for LIST_VC_AND_PRESENT_VP
//     [3] searchZKPCredentials           cache candidate referents
//     [4] fetchDefsAndSchemas            credDef/schema lookup for every candidate sub-referent →
//                                         cache referentNameMap + ZKProofParam ingredients
//     [5] checkReferentsAreAvailable     pre-check that each referent has an ACTIVE sub-referent
//
//   submit(selections:reveals:selfRaws:)   ─ after the user picks in the picker + enters self-attrs + confirms
//     [6] build selectedReferents        build UserReferent from user-selected index + reveal flag + self-attr raw
//     [7] createEncZKProof + request-verify-proof  generate the zero-knowledge proof, then submit to the verifier
//
// The instance lives for a single ZKP VP session, from preProcess → screen display → submit
// (held by AppCoordinator). The screen reads the verifier name, title and attribute/predicate captions
// directly from the instance's `presentationSummary` computed property.
//
// Pattern source: did-ca-ios `VerifyZKProofProtocol` + `VerifyProfileViewController.
// preProcessForZKP` + `ZKPSubmissionViewController.makeUserReferent`.
// Routing goes directly to the verifier (no TAS, no propose).
nonisolated final class VerifyZKProofProtocol {

    // MARK: - State accumulated across stages
    private var proofRequestProfile: _RequestProofRequestProfile? = nil
    private var hWalletToken: String = ""
    private var txId: String = ""
    private var credDefs: [String: ZKPCredentialDefinition] = [:]
    private var schemas: [String: ZKPCredentialSchema] = [:]
    /// Candidate referents cached after preProcess. Fetched ahead at the display stage to expose
    /// each attribute's sub-referents in the picker UI.
    private var availableReferent: AvailableReferent? = nil

    init() {}

    // MARK: - [1] request-proof-request-profile
    @discardableResult
    private func requestProfile(offerId: String) async throws -> _RequestProofRequestProfile {
        let request = RequestProfile(id: UUID().uuidString, offerId: offerId)
        let urlString = URLs.VERIFIER_URL + "/verifier/api/v1/request-proof-request-profile"
        let response: _RequestProofRequestProfile = try await HttpClient.sendPostRequest(
            urlString: urlString,
            request: request
        )
        self.proofRequestProfile = response
        self.txId = response.txId
        return response
    }

    // MARK: - [2] request-wallet-token
    private func requestWalletToken() async throws {
        self.hWalletToken = try await TokenGenerator.requestWalletToken(
            purpose: .LIST_VC_AND_PRESENT_VP
        )
    }

    // MARK: - [4] credDef / schema lookup
    // Collect and fetch the credDefId/schemaId of every sub-referent in the searchZKPCredentials result
    // (availableReferent). Guarantees the schema/def needed by ZKProofParam is in the cache whichever
    // sub-referent the user picks (equivalent to did-ca-ios `makeUserReferent` collecting
    // schemaIds/credDefIds from the selected sub-referents — here all candidates are covered up front in preProcess).
    // The label captions (mergedCaptionMap) are also built from these schemas.
    private func fetchDefsAndSchemas() async throws {
        guard let available = availableReferent else {
            throw VerifyZKProofError.missingProfile
        }
        let groups = available.attrReferent + available.predicateReferent
        let credDefIds = Set(groups.flatMap { $0.referent.map(\.credDefId) })
        let schemaIds = Set(groups.flatMap { $0.referent.map(\.schemaId) })

        for id in credDefIds {
            let def = try await CommunicationClient.getZKPCredentialDefinition(
                hostUrlString: URLs.API_URL,
                id: id
            )
            credDefs[id] = def
        }
        // Shares the same cache as the detail screen (CredentialStore.zkpSchemaCache) — a schema already
        // fetched on main-screen entry is reused without a new request.
        for id in schemaIds {
            schemas[id] = try await CredentialStore.shared.zkpSchema(id: id)
        }
    }

    // MARK: - [3] searchZKPCredentials — cache candidate referents
    // Secure in advance the sub-referent list to expose in each attribute's picker UI. The submit stage
    // reuses this result as-is to avoid duplicate lookups.
    private func searchCandidates() async throws {
        guard let profile = proofRequestProfile else {
            throw VerifyZKProofError.missingProfile
        }
        let proofRequest = profile.proofRequestProfile.profile.proofRequest
        self.availableReferent = try WalletAPI.shared.searchZKPCredentials(
            hWalletToken: hWalletToken,
            proofRequest: proofRequest
        )
    }

    // MARK: - [5] Status pre-check — DIDCA `checkReferentIsAvailable`
    // If no sub-referent of a referent is ACTIVE, block before entering the picker.
    // (Passes if any sub-referent is ACTIVE — the user can then pick an ACTIVE one in the picker.)
    private func checkReferentsAreAvailable() async throws {
        guard let available = availableReferent else { return }
        let groups = available.attrReferent + available.predicateReferent
        let credIds = Set(groups.flatMap { $0.referent.map(\.credId) })

        var statusByCredId: [String: VCStatusEnum] = [:]
        for credId in credIds {
            statusByCredId[credId] = try? await CredentialStore.shared.status(
                forVcId: credId,
                forceRefresh: true
            )
        }

        for referent in groups {
            let hasActive = referent.referent.contains { statusByCredId[$0.credId] == .ACTIVE }
            if !hasActive {
                throw VerifyZKProofError.noEligibleZkpCredential
            }
        }
    }

    // MARK: - [7] createEncZKProof + request-verify-proof (called from submit)
    private func requestVerifyProof(
        selectedReferents: [UserReferent],
        proofParam: ZKProofParam
    ) async throws {
        guard let profile = proofRequestProfile else {
            throw VerifyZKProofError.missingProfile
        }
        let (accE2e, encProof) = try await WalletAPI.shared.createEncZKProof(
            hWalletToken: hWalletToken,
            selectedReferents: selectedReferents,
            proofParam: proofParam,
            proofRequestProfile: profile,
            APIGatewayURL: URLs.API_URL
        )
        let request = RequestZKPVerify(
            id: UUID().uuidString,
            txId: txId,
            accE2e: accE2e,
            encProof: MultibaseUtils.encode(type: .base64, data: encProof),
            nonce: profile.proofRequestProfile.profile.proofRequest.nonce
        )
        let urlString = URLs.VERIFIER_URL + "/verifier/api/v1/request-verify-proof"
        try await HttpClient.sendPostRequest(urlString: urlString, request: request)
    }

    // MARK: - Entry point: before showing the screen (stages 1 ~ 5)
    @discardableResult
    func preProcess(offerId: String) async throws -> _RequestProofRequestProfile {
        try await requestProfile(offerId: offerId)
        try await requestWalletToken()
        try await searchCandidates()
        try await fetchDefsAndSchemas()
        try await checkReferentsAreAvailable()
        return proofRequestProfile!
    }

    // MARK: - Entry point: after user selection/confirmation/authentication (stages 5 ~ 7)
    /// `selections`: attribute / predicate referent key → selected sub-referent index.
    ///   As in did-ca-ios `ZKPSubmissionViewController.makeUserReferent`, for both sections the
    ///   user must pick in the picker which VC's sub-referent to use.
    /// `reveals`: set of attribute referent keys chosen for reveal. Irrelevant for predicate / self-attr —
    ///   predicate is fixed to isRevealed: false, and self-attr has no reveal concept at init.
    /// `selfRaws`: self-attribute referent key → raw value the user typed into the text field.
    func submit(
        selections: [String: Int],
        reveals: Set<String>,
        selfRaws: [String: String]
    ) async throws {
        guard let available = availableReferent else {
            throw VerifyZKProofError.missingProfile
        }

        // (1) If there are no candidate referents at all, matching is impossible.
        guard !available.attrReferent.isEmpty
                || !available.predicateReferent.isEmpty
                || !available.selfAttrReferent.isEmpty else {
            throw VerifyZKProofError.noEligibleZkpCredential
        }

        // (2) attribute referent — use the picker selection. Block if unselected.
        var selectedReferents: [UserReferent] = []
        for ar in available.attrReferent {
            guard !ar.referent.isEmpty else {
                throw VerifyZKProofError.noEligibleZkpCredential
            }
            guard let idx = selections[ar.key] else {
                throw VerifyZKProofError.attributeNotSelected(referentKey: ar.key)
            }
            selectedReferents.append(
                try UserReferent(
                    attrReferent: ar,
                    selectedIndex: UInt(idx),
                    isRevealed: reveals.contains(ar.key)
                )
            )
        }
        // (3) predicate referent — use the picker selection. reveal is always false.
        for pr in available.predicateReferent {
            guard !pr.referent.isEmpty else {
                throw VerifyZKProofError.noEligibleZkpCredential
            }
            guard let idx = selections[pr.key] else {
                throw VerifyZKProofError.attributeNotSelected(referentKey: pr.key)
            }
            selectedReferents.append(
                try UserReferent(
                    attrReferent: pr,
                    selectedIndex: UInt(idx),
                    isRevealed: false
                )
            )
        }
        // (4) self-attribute — the raw value the user typed. Block if empty.
        for sr in available.selfAttrReferent {
            let raw = selfRaws[sr.key] ?? ""
            guard !raw.isEmpty else {
                throw VerifyZKProofError.selfAttributeMissing(referentKey: sr.key)
            }
            selectedReferents.append(
                UserReferent(raw: raw, referentKey: sr.key, referentName: sr.name)
            )
        }

        // (5) Reuse the defs/schemas cached in the preProcess stage.
        //     The status check (.ACTIVE) was already done in preProcess's checkReferentsAreAvailable
        //     (same timing as did-ca-ios `checkReferentIsAvailable`).
        let proofParam = ZKProofParam(schemas: schemas, creDefs: credDefs)

        // (6) process → createEncZKProof + request-verify-proof
        try await requestVerifyProof(
            selectedReferents: selectedReferents,
            proofParam: proofParam
        )
    }
}

// The display models (`ZkpPresentationSummary` etc.) live in `Logic/Display/PresentationSummary.swift`.

extension VerifyZKProofProtocol {

    /// For VPRequestZkpView — builds the screen model from the profile + availableReferent + schemas
    /// filled by preProcess. did-ca-ios `ZKPSubmissionViewController` iterates the `availableReferent.*Referent`
    /// arrays as-is — not the proofRequest's dictionary. The same pattern is applied here to keep
    /// the display order deterministic.
    /// Returns an empty summary if called before preProcess.
    var presentationSummary: ZkpPresentationSummary {
        guard let profile = proofRequestProfile, let available = availableReferent else {
            return ZkpPresentationSummary(
                verifierName: "",
                title: "",
                attributes: [],
                predicates: [],
                selfAttributes: []
            )
        }
        let nameMap = schemas.values.mergedCaptionMap

        let mkClaim: (AttrReferent) -> ZkpPresentationClaim = { [self] ar in
            let candidates = ar.referent.map { sub in
                ZkpAvailableValue(
                    raw: sub.raw,
                    schemaName: schemas[sub.schemaId]?.name ?? "Unknown schema"
                )
            }
            return ZkpPresentationClaim(
                key: ar.key,
                label: nameMap[ar.name] ?? ar.name,
                availableValues: candidates
            )
        }

        return ZkpPresentationSummary(
            verifierName: profile.proofRequestProfile.profile.verifier.name,
            title: profile.proofRequestProfile.title,
            attributes: available.attrReferent.map(mkClaim),
            predicates: available.predicateReferent.map(mkClaim),
            selfAttributes: available.selfAttrReferent.map(mkClaim)
        )
    }

}
