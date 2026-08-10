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

/// OID4VCI 발급 목록 — 목록사업자의 Issuer 를 모두 읽어 Issuer 별 섹션으로 펼친다.
/// Issuer 선택 단계를 따로 두지 않으므로 진입 시 Issuer 수만큼 metadata 를 조회한다.
@Observable
final class CredentialSelectViewModel {

    /// 한 Issuer 와 그가 발급하는 credential configuration 목록.
    struct IssuerSection: Identifiable {
        let issuer: OID4VCIIssuerItem
        let metadata: IssuerMetadataResponse
        let configurations: [Configuration]
        var id: String { issuer.credentialIssuer }
    }

    /// 표시용 credential configuration. metadata 에 `display.name` 이 없어 id 를 그대로 쓴다.
    struct Configuration: Identifiable {
        let id: String
        let format: IssuerMetadataResponse.SupportedFormat

        /// SD-JWT 만 발급·저장이 가능하다 — mDoc 은 SDK 가 저장 단계에서 거부한다.
        var isIssuable: Bool {
            if case .sdjwt = format { return true }
            return false
        }

        var badge: CredentialFormat? {
            switch format {
            case .sdjwt:   return .sdJwt
            case .mdoc:    return .mDoc
            case .unknown: return nil
            }
        }
    }

    var sections: [IssuerSection] = []

    // 초기 .task 발화 전 한 프레임 동안 "발급 가능 없음" 문구가 깜빡이지 않도록 true 시작.
    var isLoading: Bool = true

    /// 목록 조회 → Issuer 별 metadata 조회 → 섹션 구성.
    /// **조회 실패와 "지원 Issuer 0건" 은 구분한다** (연동 가이드 §3) — 실패는 오류 팝업 후 Docs 복귀,
    /// 0건은 화면에 안내 문구만 남긴다.
    func load(coordinator: AppCoordinator) async {
        isLoading = true
        OverlayManager.shared.showLoading()
        defer {
            isLoading = false
            OverlayManager.shared.hideLoading()
        }

        let issuers: [OID4VCIIssuerItem]
        do {
            issuers = try await OID4VciIssuerDirectory.issuers()
        } catch {
            sections = []
            OverlayManager.shared.showErrorPopup(
                title: "Failed to load issuers",
                error: error,
                primaryAction: { coordinator.popToMain() }
            )
            return
        }

        // Issuer 수가 많지 않아 순차 조회한다. 한 Issuer 의 metadata 조회가 실패해도 나머지는 보여준다.
        var loaded: [IssuerSection] = []
        for issuer in issuers {
            // user initiation 시작점이 없는 Issuer 는 issuer-initiated(QR) 발급만 지원하므로
            // 이 화면에서는 시작할 수 없다 — 섹션을 만들지 않는다.
            guard issuer.userInitiationUri != nil else { continue }
            guard let metadata = try? await IssueOID4VcProtocol.getMetadata(
                metadataURI: issuer.credentialIssuerMetadataUri
            ) else { continue }
            // 목록이 지목한 호스트에서 온 metadata 인지 확인한다 — 오퍼 대조 기준값이 여기서 나온다.
            guard OID4VciIssuerDirectory.isMetadataConsistent(
                metadataUri: issuer.credentialIssuerMetadataUri,
                metadata: metadata
            ) else { continue }

            // dictionary 순서는 비결정적이라 id 오름차순으로 고정한다.
            let configurations = metadata.credentialConfigurationsSupported
                .map { Configuration(id: $0.key, format: $0.value.format) }
                .sorted { $0.id < $1.id }
            loaded.append(IssuerSection(issuer: issuer, metadata: metadata, configurations: configurations))
        }
        sections = loaded
    }
}
