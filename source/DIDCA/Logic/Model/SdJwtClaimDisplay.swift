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

/// Shared logic that expands SD-JWT disclosure values (`JSON`) for on-screen display.
/// The detail screen (`CredentialStore`) and the VP request screen (`OID4VPPresenter`) must use the same rules
/// so the two screens' nested claim displays don't diverge — previously each had its own copy.
// Holds only pure functions (JSON in → String/array out; no UI or state). The project's default isolation
// is MainActor, so without an explicit marker it would be bound to MainActor and calling it from the nonisolated
// OID4VPPresenter would raise an actor-isolation warning — marked nonisolated so both sides can call it freely.
nonisolated enum SdJwtClaimDisplay {

    /// SD-JWT card title. Gathered in one place so list/detail (`CredentialStore`) and the VP submission card (`OID4VPPresenter`)
    /// use the same name — even if what serves as the title changes, call sites stay the same.
    ///
    /// ⚠️ Provisional: for now `configurationId` (the config key in issuer metadata) is used as-is. This value
    /// points to the issuance configuration rather than the credential's identity and may disappear from the SDK, so it is not
    /// suitable for display. The candidate, the payload's `vct` (SD-JWT VC type), will be adopted **after agreement with another developer**.
    /// Once that is settled, only this one function needs to change.
    static func title(of item: SdJwtCredentialItem) -> String {
        item.configurationId
    }

    // MARK: - Consent items → screen rows
    //
    // Built here in one place so the detail screen (`CredentialStore`) and the VP submission consent screen (`OID4VPPresenter`)
    // draw from **the same basis and the same structure**. The basis is SDK `consentItems` — the principle that the app
    // doesn't build claim codes (SDK doc section 4) applies to both screens.
    //
    // The order is exactly as given by the SDK — the disclosure order the issuer put in the credential
    // (SDK `31f9fbb`; before that it was ascending by code). Same principle as mDoc following the issuer's
    // signing order; the app doesn't re-sort.

    /// One screen row — one parent claim and what hangs beneath it.
    struct ConsentRow {
        let item: SdJwtConsentItem
        /// Child claims with their own code. They can be disclosed separately, so each gets its own checkbox on the submission screen.
        let nested: [SdJwtConsentItem]
        /// Members inside a value disclosed together with the parent that can't be excluded separately. Display only.
        let rideAlong: [(label: String, value: String)]
    }

    /// `consentItems` → list of screen rows. First strips out the two kinds not shown on screen.
    ///
    /// - `isAmbiguous`: one code points to two or more claims. Which one was consented to can't be determined and
    ///   the SDK fails the submission, so consent that can't be honored is not collected.
    /// - `isSelectivelyDisclosable == false`: a claim the issuer put in plaintext, so there is no way to hide it.
    ///   Excluded from the list like the current screen (decision 2026-08-12). On the submission screen, plaintext
    ///   codes the verifier requires are carried separately as `requiredCodes` and still go into the submission set.
    ///
    /// Nesting is determined **for display only** by prefix relations between codes — the codes themselves are neither split nor built.
    /// If the issuer sends `address.street_address` as a single-piece name, it is wrongly folded under `address` on screen,
    /// but the code is unchanged, so submission is unaffected.
    static func consentRows(_ items: [SdJwtConsentItem]) -> [ConsentRow] {
        let rows = items.filter { !$0.isAmbiguous && $0.isSelectivelyDisclosable }
        let codes = Set(rows.map(\.code))

        var childrenByRoot: [String: [SdJwtConsentItem]] = [:]
        var roots: [SdJwtConsentItem] = []
        for item in rows {
            if let root = rootCode(of: item.code, in: codes) {
                childrenByRoot[root, default: []].append(item)
            } else {
                roots.append(item)
            }
        }

        return roots.map { root in
            // Drop members inside the value that have their own code (= nested) — keeping them would show the same value twice,
            // once as a row with a checkbox and once without.
            let rideAlong = childRows(root.value)
                .filter { !codes.contains(root.code + $0.keySuffix) }
                .map { (label: $0.label, value: $0.value) }
            return ConsentRow(item: root,
                              nested: childrenByRoot[root.code] ?? [],
                              rideAlong: rideAlong)
        }
    }

    /// Display value of a consent item — image detection is based on the claim name whitelist (see `ImageClaim`).
    /// The name is the last piece, not the full code path — that is the name the issuer gave.
    static func value(of item: SdJwtConsentItem) -> ClaimValue {
        ImageClaim.claimValue(name: item.claimName, text: scalarString(item.value))
    }

    /// The code of the **outermost** claim containing `code` — nil if none (it is itself top-level).
    ///
    /// Since the screen draws only one level, attach to the top level, not the nearest parent. Attaching a grandchild to its parent
    /// would make the whole row vanish from the screen when that parent in turn goes under someone else.
    private static func rootCode(of code: String, in codes: Set<String>) -> String? {
        codes
            .filter { $0.count < code.count && code.hasPrefix($0) && isBoundary(code, after: $0) }
            .min { $0.count < $1.count }
    }

    /// Whether what follows the prefix is a boundary (`.` or `[`) — prevents `addressed` from being caught as a child of `address`.
    private static func isBoundary(_ code: String, after prefix: String) -> Bool {
        let next = code[code.index(code.startIndex, offsetBy: prefix.count)]
        return next == "." || next == "["
    }

    // MARK: - Value conversion

    /// Scalar `AnyJSON` → display string. `consentItems` (SDK) supplies values in this type.
    ///
    /// Per the JSON spec numbers arrive as a single `Double`, so if there is no fractional part write it back as an integer —
    /// used as-is, the issuer's `1990` would appear on screen as `1990.0`.
    static func scalarString(_ json: AnyJSON) -> String {
        switch json {
        case .string(let value):    return value
        case .number(let value):    return numberString(value)
        case .bool(let flag):       return flag ? "true" : "false"
        case .null:                 return ""
        case .object, .array:       return ""
        }
    }

    private static func numberString(_ value: Double) -> String {
        guard value.rounded() == value, abs(value) < 1e15 else { return String(value) }
        return String(Int64(value))
    }

    /// Child items of a composite value (object/array). Empty array for scalars or empty values.
    /// - object → one row per key. The label is **the issued key verbatim** (no case/separator changes —
    ///   keys are data, not display copy, and must be visually comparable with the names the verifier requested).
    ///   `AnyJSON.object` is a `Dictionary` whose iteration order varies per run, so sort by key to fix it.
    /// - array  → unlabeled rows (label=""). The index is not a value the issuer sent but a number attached to the order,
    ///   so showing it would read as if a nonexistent field existed. Row order already expresses the order.
    ///   Rows with an empty label draw only the value (caller-side `ClaimRow` / `VpClaimGroup`).
    ///
    /// `keySuffix` is the piece (`.field` / `[i]`) that, appended to the parent code, points to this member.
    /// **It must not be used to build submission codes** — the only codes that go out are the values given by SDK
    /// `consentItems`. Its only use here is checking against that list "is this member a separately disclosable claim"
    /// (and the value used after the check is also the SDK-given code), which is why the index is kept.
    static func childRows(_ json: AnyJSON) -> [(label: String, value: String, keySuffix: String)] {
        switch json {
        case .object(let keyValues):
            return keyValues.sorted { $0.key < $1.key }
                .map { (label: $0.key, value: scalarString($0.value), keySuffix: ".\($0.key)") }
        case .array(let elements):
            return elements.enumerated().map {
                (label: "", value: scalarString($0.element), keySuffix: "[\($0.offset)]")
            }
        default:
            return []
        }
    }
}
