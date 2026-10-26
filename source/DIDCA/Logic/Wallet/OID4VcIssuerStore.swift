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

/// **Which issuer issued** each OID4VCI credential (SD-JWT·mDoc) — kept so the issuer metadata passed to server
/// revocation (`requestRevokeOID4VC`) can be fetched again. The SDK's stored item (`CredentialItem`) has no issuer.
///
/// One issuer issues many credentials, so the data is split into two tables.
///   - `oid4vcIssuers` [issuerKey: credential_issuer] — the canonical issuer record. One per issuer.
///   - `oid4vcCredentialIssuers` [credential id: issuerKey] — per-credential reference pointing at its issuer.
///
/// issuerKey is the value normalized by `OID4VciIssuerDirectory.normalizedIssuer` (the raw string if not a URL), so
/// the same issuer written differently collapses into one record. The canonical value keeps the raw string used for
/// the metadata lookup at issuance — so revocation builds the same well-known path from the same string.
///
/// The metadata response itself is not stored. Revocation must use the `credential_revocation_endpoint`·`nonce_endpoint`
/// current at that time, so it is fetched fresh every time.
///
/// A canonical record is deleted along with its last reference (`remove`·`prune`). Even if the tables drift, a lookup
/// succeeds only when both exist, so a broken reference reads as "issuer unknown".
nonisolated enum OID4VcIssuerStore {

    private static let defaults = UserDefaults.standard
    private static var issuersKey: String { PreferenceKey.oid4vcIssuers.rawValue }
    private static var referencesKey: String { PreferenceKey.oid4vcCredentialIssuers.rawValue }

    /// The credential's issuer (`credential_issuer`) — nil if not recorded at issuance (issued before this feature).
    static func issuer(forCredentialId id: String) -> String? {
        guard let issuerKey = references()[id] else { return nil }
        return issuers()[issuerKey]
    }

    /// Records one entry right after issuance. If the issuer already exists, refreshes the canonical record with the latest raw value and just adds the reference.
    static func register(credentialIssuer: String, forCredentialId id: String) {
        let issuerKey = OID4VciIssuerDirectory.normalizedIssuer(credentialIssuer) ?? credentialIssuer
        var issuers = issuers()
        issuers[issuerKey] = credentialIssuer
        var references = references()
        references[id] = issuerKey
        save(issuers: issuers, references: references)
    }

    /// Removes the reference after credential deletion — also deletes the canonical record if no credential points to that issuer anymore.
    static func remove(credentialId id: String) {
        var references = references()
        guard references.removeValue(forKey: id) != nil else { return }
        save(issuers: issuers(), references: references)
    }

    /// Cleans up keeping only credential ids still in the wallet — sweeps references left by failures mid-deletion or
    /// deletion via another path, and the canonical records left because of them. Called when the list is reloaded.
    static func prune(keeping ids: Set<String>) {
        let references = references()
        let kept = references.filter { ids.contains($0.key) }
        guard kept.count != references.count else { return }
        save(issuers: issuers(), references: kept)
    }

    // MARK: - Storage

    private static func issuers() -> [String: String] {
        (defaults.dictionary(forKey: issuersKey) as? [String: String]) ?? [:]
    }

    private static func references() -> [String: String] {
        (defaults.dictionary(forKey: referencesKey) as? [String: String]) ?? [:]
    }

    /// Writes both tables together — unreferenced canonical records are dropped here.
    private static func save(issuers: [String: String], references: [String: String]) {
        let referenced = Set(references.values)
        let issuers = issuers.filter { referenced.contains($0.key) }
        defaults.setValue(issuers, forKey: issuersKey)
        defaults.setValue(references, forKey: referencesKey)
    }
}
