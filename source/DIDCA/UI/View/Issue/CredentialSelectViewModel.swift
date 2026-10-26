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

/// OID4VCI issuance list — reads all of the directory provider's Issuers and lays them out in per-Issuer sections.
/// There is no separate Issuer selection step, so on entry metadata is fetched once per Issuer.
@Observable
final class CredentialSelectViewModel {

    /// One Issuer and the list of credential configurations it issues.
    struct IssuerSection: Identifiable {
        let issuer: OID4VCIIssuerItem
        let metadata: IssuerMetadataResponse
        let configurations: [Configuration]
        var id: String { issuer.credentialIssuer }
    }

    /// Credential configuration for display. metadata has no `display.name`, so the id is used as-is.
    struct Configuration: Identifiable {
        let id: String
        let format: IssuerMetadataResponse.SupportedFormat

        /// SD-JWT and mDoc can be issued and stored. The issuance path itself is format-agnostic (the SDK handles
        /// through storage); all the app knows is whether it can draw it — so this check is about display support.
        /// (Before SDK 3.0.0, mDoc storage was rejected, so only SD-JWT was enabled.)
        var isIssuable: Bool {
            switch format {
            case .sdjwt, .mdoc: return true
            case .unknown:      return false
            }
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

    // Starts true so the "nothing issuable" text doesn't flash for one frame before the initial .task fires.
    var isLoading: Bool = true

    /// Fetch list → fetch metadata per Issuer → build sections.
    /// **A fetch failure and "0 supported Issuers" are distinguished** (integration guide §3) — failure shows an error popup and returns to Docs,
    /// 0 results leaves only a notice text on screen.
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

        // There aren't many Issuers, so fetch sequentially. If one Issuer's metadata fetch fails, the rest are still shown.
        var loaded: [IssuerSection] = []
        for issuer in issuers {
            // An Issuer without a user-initiation entry point only supports issuer-initiated (QR) issuance,
            // so it can't be started from this screen — no section is created.
            guard issuer.userInitiationUri != nil else { continue }
            guard let metadata = try? await IssueOID4VcProtocol.getMetadata(
                metadataURI: issuer.credentialIssuerMetadataUri
            ) else { continue }
            // Verify the metadata came from the host the list pointed to — the reference value for offer matching comes from here.
            guard OID4VciIssuerDirectory.isMetadataConsistent(
                metadataUri: issuer.credentialIssuerMetadataUri,
                metadata: metadata
            ) else { continue }

            // Dictionary order is nondeterministic, so fix it by ascending id.
            let configurations = metadata.credentialConfigurationsSupported
                .map { Configuration(id: $0.key, format: $0.value.format) }
                .sorted { $0.id < $1.id }
            loaded.append(IssuerSection(issuer: issuer, metadata: metadata, configurations: configurations))
        }
        sections = loaded
    }
}
