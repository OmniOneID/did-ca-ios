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
    /// 후보 referent 가 비어있거나, 어떤 referent 에도 ACTIVE 한 sub-referent 가 없음 — picker 진입 전 차단.
    case noEligibleZkpCredential
    /// 사용자가 picker 로 attribute/predicate 값을 아직 고르지 않음 — submit 시점에 모든 항목이 선택돼 있어야 함.
    case attributeNotSelected(referentKey: String)
    /// self-attribute 입력값이 비어있음.
    case selfAttributeMissing(referentKey: String)
}

// MARK: - ZKP VP 제출 흐름 (OpenDID SDK 사용 예시)
//
// 진입점은 두 단계로 나뉜다:
//
//   preProcess(offerId:)                   ─ QR 스캔 직후, 화면 표시 직전
//     [1] request-proof-request-profile  verifier 프로필(요구 attr/predicate, nonce) 수령
//     [2] request-wallet-token           LIST_VC_AND_PRESENT_VP 용도
//     [3] searchZKPCredentials           후보 referent 캐시
//     [4] fetchDefsAndSchemas            모든 후보 sub-referent 의 credDef/schema lookup →
//                                         referentNameMap + ZKProofParam 재료 캐시
//     [5] checkReferentsAreAvailable     각 referent 에 ACTIVE sub-referent 가 있는지 사전 검증
//
//   submit(selections:reveals:selfRaws:)   ─ 사용자가 picker 로 선택 + self-attr 입력 + 확인 후
//     [6] selectedReferents 구성         사용자 선택 index + reveal flag + self-attr raw 로 UserReferent 빌드
//     [7] createEncZKProof + request-verify-proof  영지식 증명 생성 후 verifier 제출
//
// 인스턴스는 preProcess → 화면 표시 → submit 까지 단일 ZKP VP 세션 동안 유지된다
// (AppCoordinator 가 보유). 화면은 인스턴스의 `presentationSummary` computed
// property 로 verifier 이름·title·attribute/predicate 캡션을 직접 조회.
//
// 패턴 출처: did-ca-ios `VerifyZKProofProtocol` + `VerifyProfileViewController.
// preProcessForZKP` + `ZKPSubmissionViewController.makeUserReferent`.
// 라우팅은 verifier 직접 (TAS 경유·propose 없음).
nonisolated final class VerifyZKProofProtocol {

    // MARK: - 단계별 누적 상태
    private var proofRequestProfile: _RequestProofRequestProfile? = nil
    private var hWalletToken: String = ""
    private var txId: String = ""
    private var credDefs: [String: ZKPCredentialDefinition] = [:]
    private var schemas: [String: ZKPCredentialSchema] = [:]
    /// preProcess 후 캐시되는 후보 referent. attribute 별 sub-referent 들을 picker UI 에
    /// 노출하기 위해 화면 표시 단계에 미리 조회한다.
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
    // searchZKPCredentials 결과(availableReferent)의 모든 sub-referent 의 credDefId/schemaId
    // 를 모아 fetch. 사용자가 어떤 sub-referent 를 골라도 ZKProofParam 에 필요한 schema/def 가
    // 캐시에 포함되도록 보장 (did-ca-ios `makeUserReferent` 가 선택된 sub-referent 기반으로
    // schemaIds/credDefIds 를 모으는 것과 등가 — preProcess 단계에서 미리 모든 후보를 cover).
    // 라벨 caption(mergedCaptionMap) 도 이 schemas 에서 빌드.
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
        // 상세화면과 같은 캐시(CredentialStore.zkpSchemaCache)를 공유 — 메인 진입 때
        // 이미 받아둔 schema 면 재요청 없이 재사용된다.
        for id in schemaIds {
            schemas[id] = try await CredentialStore.shared.zkpSchema(id: id)
        }
    }

    // MARK: - [3] searchZKPCredentials — 후보 referent 캐시
    // attribute 별 picker UI 에 노출할 sub-referent 목록을 미리 확보. submit 단계에서도
    // 이 결과를 그대로 재사용해 중복 조회를 막는다.
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

    // MARK: - [5] 상태 사전 검증 — DIDCA `checkReferentIsAvailable`
    // 각 referent 의 sub-referent 들 중 단 하나라도 ACTIVE 가 없으면 picker 진입 전 차단.
    // (어떤 sub-referent 라도 ACTIVE 면 통과 — 사용자가 거기서 picker 로 ACTIVE 한 걸 고를 수 있다.)
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

    // MARK: - [7] createEncZKProof + request-verify-proof (submit 호출)
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

    // MARK: - 진입점: 화면 표시 전 (단계 1 ~ 5)
    @discardableResult
    func preProcess(offerId: String) async throws -> _RequestProofRequestProfile {
        try await requestProfile(offerId: offerId)
        try await requestWalletToken()
        try await searchCandidates()
        try await fetchDefsAndSchemas()
        try await checkReferentsAreAvailable()
        return proofRequestProfile!
    }

    // MARK: - 진입점: 사용자 선택/확인/인증 후 (단계 5 ~ 7)
    /// `selections`: attribute / predicate referent key → 선택된 sub-referent index.
    ///   did-ca-ios `ZKPSubmissionViewController.makeUserReferent` 와 동일하게 두 섹션 모두
    ///   사용자가 picker 로 어느 VC 의 sub-referent 를 쓸지 골라야 한다.
    /// `reveals`: reveal 선택한 attribute referent key 집합. predicate / self-attr 는 무관 —
    ///   predicate 는 isRevealed: false 고정, self-attr 는 init 시 reveal 개념 없음.
    /// `selfRaws`: self-attribute referent key → 사용자가 텍스트필드로 입력한 raw 값.
    func submit(
        selections: [String: Int],
        reveals: Set<String>,
        selfRaws: [String: String]
    ) async throws {
        guard let available = availableReferent else {
            throw VerifyZKProofError.missingProfile
        }

        // (1) 후보 referent 가 하나도 없으면 매칭 불가.
        guard !available.attrReferent.isEmpty
                || !available.predicateReferent.isEmpty
                || !available.selfAttrReferent.isEmpty else {
            throw VerifyZKProofError.noEligibleZkpCredential
        }

        // (2) attribute referent — picker 선택값 사용. 미선택 차단.
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
        // (3) predicate referent — picker 선택값 사용. reveal 은 항상 false.
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
        // (4) self-attribute — 사용자가 직접 입력한 raw 값. 빈 값 차단.
        for sr in available.selfAttrReferent {
            let raw = selfRaws[sr.key] ?? ""
            guard !raw.isEmpty else {
                throw VerifyZKProofError.selfAttributeMissing(referentKey: sr.key)
            }
            selectedReferents.append(
                UserReferent(raw: raw, referentKey: sr.key, referentName: sr.name)
            )
        }

        // (5) preProcess 단계에서 캐시한 defs/schemas 재사용.
        //     상태 검증(.ACTIVE) 은 preProcess 의 checkReferentsAreAvailable 에서 이미 수행됨
        //     (did-ca-ios `checkReferentIsAvailable` 와 동일 시점).
        let proofParam = ZKProofParam(schemas: schemas, creDefs: credDefs)

        // (6) process → createEncZKProof + request-verify-proof
        try await requestVerifyProof(
            selectedReferents: selectedReferents,
            proofParam: proofParam
        )
    }
}

// 표시 모델(`ZkpPresentationSummary` 등)은 `Logic/Display/PresentationSummary.swift` 에 있다.

extension VerifyZKProofProtocol {

    /// VPRequestZkpView 표시용 — preProcess 가 채운 profile + availableReferent + schemas 로
    /// 화면 모델을 구성. did-ca-ios `ZKPSubmissionViewController` 는 `availableReferent.*Referent`
    /// 배열을 그대로 순회한다 — proofRequest 의 dictionary 를 도는 게 아니라. 같은 패턴 적용해
    /// 화면 표시 순서를 결정적으로 유지한다.
    /// preProcess 전에 호출하면 빈 summary 가 반환됨.
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
