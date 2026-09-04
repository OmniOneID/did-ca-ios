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

// 화면이 버튼 하나로 시작하는 종결 동작 — 제출(VP / OID4VP / ZKP)과 폐기.
// 셋 다 같은 골격이다: 인증 → 로딩 → 프로토콜 호출 → 성공 팝업 또는 오류 팝업 → 메인 복귀.
// 스캔에서 시작하는 흐름(발급·제시 진입)은 QRRouter 소관 — 여기는 사용자가 화면에서
// 직접 누르는 마지막 단계만 둔다.
extension AppCoordinator {

    /// VC 삭제 — 인증 → (W3C) 서버 폐기 propose/request/confirm + 지갑 삭제 / (SD-JWT) 로컬 삭제
    /// → 목록 갱신 → docs 복귀. 성공 시에만 docs 로 이동(목록에서 카드 사라짐), 실패 시 카드 유지
    /// + 오류 팝업 (설계 VC-E-01).
    ///
    /// OID4VCI 발급분(SD-JWT·mDoc)은 서버 폐기 흐름이 없어 `deleteOID4VCs` 로 로컬 삭제만 한다
    /// (저장소가 W3C `WalletAPI` 와 분리돼 있어 `RevokeVcProtocol` 경로로는 못 지운다). 로컬 삭제는
    /// 서버 서명이 없어 인증 게이트(presentAuth)를 건너뛴다 — W3C 폐기만 PIN/BIO 가 필요하다.
    func revokeCredential(_ cred: Credential) async {
        let isOID4VC = cred.badge == .sdJwt || cred.badge == .mDoc

        // W3C 폐기는 서버 서명용 인증이 필요. OID4VC 로컬 삭제는 인증 없이 진행한다.
        var passcode: String?
        if !isOID4VC {
            guard let auth = await presentAuth() else { return }
            passcode = auth.passcode
        }

        OverlayManager.shared.showLoading()
        defer { OverlayManager.shared.hideLoading() }
        do {
            if isOID4VC {
                let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .REMOVE_VC)
                try WalletAPI.shared.deleteOID4VCs(hWalletToken: hWalletToken, ids: [cred.id])
            } else {
                try await RevokeVcProtocol.revoke(vcId: cred.id, passcode: passcode)
            }
            // 지갑을 다시 읽어 목록 동기화 — 삭제된 VC(및 페어 ZKP)가 빠진다.
            credentials = await CredentialStore.shared.loadCredentials()
            popToMain()
        } catch {
            // VC-E-01: 삭제 실패 → 서버 메시지 있으면 표시, 없으면 fallback. 카드 유지(화면 이동 없음).
            OverlayManager.shared.showErrorPopup(
                title: "Failed to delete",
                error: error,
                fallback: "Failed to delete. Try again."
            )
        }
    }

    /// 일반 VP 제출 — 인증 → VerifyVcProtocol.submit(암호화 VP) → 성공 팝업 → 메인 복귀.
    /// - parameter selectedCodes: VPRequestView 에서 사용자가 체크한 claim — credentialId → code 집합.
    ///   제출 대상 산출은 화면에 띄운 `verifySummary` 를 근거로 하며, 여기서 VC 를 다시 고르지 않는다.
    func submitVp(selectedCodes: [String: Set<String>] = [:]) async {
        guard let profile = verifyProfile, let summary = verifySummary else { return }
        // VAUTH: verifier 가 process.authType 으로 요구한 인증수단을 강제한다.
        guard let auth = await presentAuth(for: profile.profile.profile.process.authType) else { return }

        OverlayManager.shared.showLoading()
        defer { OverlayManager.shared.hideLoading() }
        do {
            try await VerifyVcProtocol.submit(profile: profile, summary: summary,
                                              passcode: auth.passcode, selectedCodes: selectedCodes)
            OverlayManager.shared.showPopup(
                title: "Submission successful",
                message: "Your information has been shared successfully.",
                primaryButtonTitle: "Done",
                primaryAction: { [weak self] in self?.popToMain() }
            )
        } catch {
            // PRES-E-01: 제출 실패 → OK 시 Certs(Docs)로 복귀.
            OverlayManager.shared.showErrorPopup(
                title: "Failed to submit",
                error: error,
                primaryAction: { [weak self] in self?.popToMain() }
            )
        }
    }

    /// OID4VP 제출 — 인증 → OID4VPPresenter.submit(vp_token POST) → 성공 팝업 → 메인 복귀.
    ///
    /// 인증수단은 verifier 가 아니라 **제출 대상의 발급 시 바인딩 키**가 정한다. OID4VP 인가요청에는
    /// verifier 의 authType 지정이 없고, SD-JWT 는 발급 때 고정된 `kid` 로만 서명되기 때문이다
    /// (`presentAuth(forBindingKeyIds:)` 참조). 판정 근거는 화면에 띄운 요약 그대로다 — 표시와
    /// 제출이 같은 매칭 결과를 쓰므로 대상이 어긋나지 않는다.
    /// - parameter selectedCodes: 사용자가 공개에 동의한 claim — credentialId → code 집합.
    ///   제출은 `verifier 요청 ∩ 사용자 동의` 로 좁혀진다(포맷 무관 — W3C DCQL claim 쿼리가 추가돼도 동일).
    func submitOID4VP(selectedCodes: [String: Set<String>] = [:]) async {
        guard let authRequest = oid4vpRequest else { return }

        // 인증수단 판정은 **실제로 제출되는** 문서만 본다. 후보 전체를 보면 사용자가 고르지 않은
        // 카드의 바인딩까지 세어 엉뚱한 인증을 요구한다 (bio 만 제출하는데 PIN 패드가 뜨는 증상).
        // 포함 규칙은 `OID4VPPresenter.applyConsent` 와 같다 — 화면이 담아 보낸 **선택된 1건**이
        // 곧 제출 대상이므로, 키가 있는 문서만 센다.
        let submittedKeyIds = (oid4vpSummary?.documents ?? [])
            .filter { selectedCodes[$0.credentialId] != nil }
            .compactMap(\.bindingKeyId)

        guard let auth = await presentAuth(forBindingKeyIds: submittedKeyIds) else { return }

        OverlayManager.shared.showLoading()
        defer { OverlayManager.shared.hideLoading() }
        do {
            try await OID4VPPresenter.submit(authRequest: authRequest, passcode: auth.passcode, selectedCodes: selectedCodes)
            OverlayManager.shared.showPopup(
                title: "Submission successful",
                message: "Your information has been shared successfully.",
                primaryButtonTitle: "Done",
                primaryAction: { [weak self] in self?.popToMain() }
            )
        } catch {
            // PRES-E-01 (OID4VP): 제출 실패 → OK 시 Certs(Docs)로 복귀.
            OverlayManager.shared.showErrorPopup(
                title: "Failed to submit",
                error: error,
                primaryAction: { [weak self] in self?.popToMain() }
            )
        }
    }

    /// ZKP VP 제출 — preProcess 단계의 인스턴스 재사용해 submit → 성공 팝업 → 메인 복귀.
    /// `createEncZKProof` 는 holder DID 서명이 들어가지 않아 passcode 가 필요 없고, did-ca-ios
    /// `ZKPSubmissionViewController.submitAction` 도 인증 단계 없이 바로 호출 — 동일하게 PIN
    /// 인증 단계 없음.
    /// selections / reveals / selfRaws 는 모두 coordinator 가 보유한 사용자 입력 상태에서 그대로 전달.
    func submitZkpVp() async {
        guard let proto = zkpProto else { return }

        OverlayManager.shared.showLoading()
        defer { OverlayManager.shared.hideLoading() }
        do {
            try await proto.submit(
                selections: zkpAttrSelections,
                reveals: zkpReveals,
                selfRaws: zkpSelfRaws
            )
            OverlayManager.shared.showPopup(
                title: "Submission successful",
                message: "Your information has been shared successfully.",
                primaryButtonTitle: "Done",
                primaryAction: { [weak self] in self?.popToMain() }
            )
        } catch {
            // PRES-E-01 (ZKP): 제출 실패 → OK 시 Certs(Docs)로 복귀.
            OverlayManager.shared.showErrorPopup(
                title: "Failed to submit",
                error: error,
                primaryAction: { [weak self] in self?.popToMain() }
            )
        }
    }

    // MARK: - 발급 후처리

    // 발급 진입점은 셋이다 — 목록 발급(AddCertificateViewModel), QR 발급·OID4VCI(QRRouter).
    // 프로토콜 호출까지는 각자 다르지만 끝맺음은 같아서 아래 둘로 모았다.

    /// 발급 성공 꼬리 — 지갑을 다시 읽어 목록을 갱신하고 성공 화면으로 이동한다.
    ///
    /// 성공 화면 제목은 **갱신된 목록에서 찾은 카드 이름**이다. 목록·상세와 같은 값을 쓰므로
    /// 세 화면의 표기가 어긋나지 않는다.
    ///
    /// - parameter vcId: 방금 발급된 크리덴셜의 id. 세 진입점 모두 발급 결과로 이 값을 받는다
    ///   (W3C=`IssueVcProtocol` 의 vcId, OID4VCI=저장된 SD-JWT 의 id). 따라서 목록에서 못 찾는
    ///   경우는 없다 — 그럼에도 못 찾으면 제목 없이 성공 화면만 띄운다(발급 자체는 성공이므로).
    func completeIssuance(vcId: String) async {
        credentials = await CredentialStore.shared.loadCredentials()
        issuedTitles = credentials.first(where: { $0.id == vcId }).map { [$0.name] } ?? []
        setStack([.issueSuccess])
    }

    /// 발급 실패 꼬리 — ISS-E-01~03. OK 를 누르면 Certs(Docs)로 복귀한다.
    /// 로딩은 따로 내리지 않는다 — `showErrorPopup` → `showPopup` 이 이미 `hideLoading()` 한다.
    ///
    /// - parameter fallback: 응답에 메시지가 없는 오류(`.other`)일 때 대신 띄울 문구.
    ///   TXC-E-01 의 "Wrong code." 가 이 경로다 — 서버·네트워크 메시지가 있으면 그쪽이 우선한다.
    func failIssuance(_ error: Error, fallback: String? = nil) {
        OverlayManager.shared.showErrorPopup(
            title: "Failed to issue",
            error: error,
            fallback: fallback,
            primaryAction: { [weak self] in self?.popToMain() }
        )
    }
}
