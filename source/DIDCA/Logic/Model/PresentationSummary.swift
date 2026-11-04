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

// MARK: - VP request screen display data
//
// Shared display model built by the protocol layer and consumed by the screen. Not tied to a specific protocol —
// plain VP (`VerifyVcProtocol`) and OID4VP (`OID4VPPresenter`) build the same `VpPresentationSummary`
// and hand it to the same screen (`VPRequestView`).

struct VpPresentationClaim {
    /// The claim code that goes out in the submission. **Exactly as given by the SDK**; the app neither builds nor splits it
    /// (SD-JWT/mDoc: `consentItems`, W3C: VC claim code).
    ///
    /// `nil` means **a row that is not a submission unit** — there is no way to exclude it, so it goes out with its parent/element
    /// (SD-JWT rideAlong, elements of an mDoc composite value). No checkbox is drawn.
    let code: String?
    let label: String
    /// Text or image (portrait etc.). An image replaces the value text — see `ImageClaim` for detection.
    let value: ClaimValue
    /// Belongs to the REQUIRED section — the user can't remove it and it is always submitted. **No checkbox is drawn**
    /// (no greyed-out disabled checkbox is used).
    /// `false` means the OPTIONAL section, and it **starts unchecked** (opt-in).
    ///
    /// Required-ness only flows down from the parent and propagates to the whole subtree — if the parent is REQUIRED, so are the children.
    let required: Bool
    /// Child items. If empty, shown as a single row; otherwise as a collapsible group (only one level is drawn).
    ///
    /// **Children have no individual checkboxes** — a group is toggled as a whole by the single parent checkbox.
    /// A child's `code` is used only when building the submission set (turning on the parent sends the child codes too).
    /// Always empty for W3C VCs.
    var children: [VpPresentationClaim] = []
}

/// A document to submit shown on the VP request screen (one credential).
///
/// So that screen and submission rely on the same basis, the protocol layer computes it once and stores it here.
/// A card is described by four sets — exposed (`claims`), required (`claims[].required`),
/// checked (held by the screen), submitted (`requiredCodes ∪ checked`).
struct VpPresentationDocument {
    let credentialId: String
    let title: String
    /// The exposed set. REQUIRED is always submitted; OPTIONAL starts unchecked.
    let claims: [VpPresentationClaim]
    /// Codes always submitted regardless of toggles — the same set as the REQUIRED rows (and their children) of the exposed set.
    ///
    /// **Required items are not hidden from the screen** — even if the OpenDID profile's `requiredClaims` lie
    /// outside `displayClaims`, they are merged into the exposed set and drawn. This set is still carried separately
    /// so the submission output doesn't depend on traversing the exposed tree (child codes are gathered in one place).
    let requiredCodes: Set<String>
    /// Only for OID4VC-issued (SD-JWT/mDoc) — the signing key id this credential was **bound to at issuance**
    /// (`KeyIdName.pin` / `.bio`).
    /// The presentation authentication method isn't chosen by the user but determined by this value: the SDK signs each credential
    /// with `walletCore.sign(keyId: item.kid, …)`, so the binding can't be changed.
    /// nil for W3C cards (there the signing key depends on whether a passcode is present, so the user can choose).
    let bindingKeyId: String?
}

/// Verifier name + list of submission **candidates** — for VPRequestView display.
///
/// With 2+ candidates the screen splits into radio option cards and **only one of them is submitted**.
/// Only ACTIVE candidates are included — if 0, the protocol layer aborts as not submittable.
struct VpPresentationSummary {
    let verifierName: String
    let documents: [VpPresentationDocument]
}

// MARK: - ZKP VP request screen display data (for `VPRequestZkpView`)

/// Display of one sub-referent — bundles the raw value with the schema name it came from,
/// so sub-referents with the same raw value are distinguished as different rows in the picker.
/// Counterpart of the cell in did-ca-ios `AttrSelectionViewController` (nameLabel = schema.name, valueLabel = raw).
struct ZkpAvailableValue {
    let raw: String
    let schemaName: String
}

struct ZkpPresentationClaim {
    /// AvailableReferent.attrReferent[].key — key of the coordinator's selection/input dictionary.
    let key: String
    let label: String
    /// Candidates the user can pick in the picker — 1:1 with AvailableReferent.attrReferent[].referent[].
    /// The index is used directly as the selectedIndex of UserReferent(attrReferent:selectedIndex:).
    /// As in did-ca-ios, predicates also provide a candidate list for the user to choose. Empty for self-attributes.
    let availableValues: [ZkpAvailableValue]
}

/// VPRequestZkpView display model — as in did-ca-ios `ZKPSubmissionViewController`,
/// the three groups Attributes / Predicates / Self-Attributes are listed flat on a single screen
/// (no per-document grouping).
struct ZkpPresentationSummary {
    let verifierName: String
    let title: String
    let attributes: [ZkpPresentationClaim]
    let predicates: [ZkpPresentationClaim]
    let selfAttributes: [ZkpPresentationClaim]
}
