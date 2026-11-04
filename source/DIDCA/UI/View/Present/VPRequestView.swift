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

import SwiftUI

/// One child line of a group (compound-value disclosure / mDoc compound element) — **display only**.
/// Children have no checkbox of their own. The single parent checkbox decides submission,
/// and child codes only follow the parent via its `descendantCodes`.
struct VpChildRow: Identifiable {
    let id = UUID()
    let label: String
    let value: ClaimValue
}

/// One row = one submission unit. If it has children it is drawn as a collapsible group (one level only).
struct VpClaim: Identifiable {
    let id = UUID()
    /// Claim code sent on submit. `nil` means a display-only row that can't be excluded on its own, so no checkbox is drawn.
    let code: String?
    let label: String
    let value: ClaimValue
    /// Child codes that move **together** when this row is toggled — all-or-nothing.
    ///
    /// An SD-JWT child disclosure always carries along the ancestor disclosures that conceal it
    /// (SDK `SDJWTPresenter.resolveDisclosures`). Letting parent and child move independently makes screen and submission diverge.
    let descendantCodes: [String]
    let children: [VpChildRow]

    var isGroup: Bool { !children.isEmpty }
    /// Every code touched when the checkbox toggles this row.
    var toggledCodes: Set<String> {
        guard let code else { return [] }
        return Set([code] + descendantCodes)
    }
}

/// One submission candidate = one card. With 2+ candidates they become radio option cards and **only one is submitted**.
struct VpOption: Identifiable {
    let id = UUID()
    let credentialId: String
    let title: String
    /// Codes always submitted regardless of checks. If non-empty, Submit is always enabled.
    let requiredCodes: Set<String>
    /// REQUIRED section — no checkboxes are drawn (no greyed-out disabled checkboxes).
    let required: [VpClaim]
    /// OPTIONAL section — **starts unchecked** (opt-in).
    let optional: [VpClaim]

    /// Codes handled by Select all — display-only rows excluded.
    var optionalCodes: Set<String> {
        optional.reduce(into: Set<String>()) { $0.formUnion($1.toggledCodes) }
    }
}

/// VP request (presentation) screen. Verifier and candidate list come from `VpPresentationSummary`
/// (regular VP = `VerifyVcProtocol`, OID4VP = `OID4VPPresenter` — same type, same screen).
struct VPRequestView: View {
    var summary: VpPresentationSummary?
    var onBack: () -> Void = {}
    /// Submission payload — holds **only the one selected candidate** (credentialId → checked codes).
    ///
    /// Unselected candidates have no key at all. The receivers (`VerifyVcProtocol.submit` ·
    /// `OID4VPPresenter.applyConsent`) read "no key = not submitted" and drop them.
    /// Even with 0 checks, REQUIRED items are still submitted, so an empty set doesn't mean "submit nothing".
    var onSubmit: ([String: Set<String>]) async -> Void = { _ in }

    @State private var options: [VpOption] = []
    /// Candidate chosen by radio. With a single candidate, that one is always selected.
    @State private var selectedOption: UUID?
    /// Codes the user turned on in the selected candidate. Cleared entirely when the candidate changes.
    @State private var checked: Set<String> = []
    /// Expanded cards — **several can be expanded at once**.
    ///
    /// Tapping a document header opens/closes only that card and leaves the others alone — candidates must be
    /// expandable side by side for comparison, and collapsing a card above would make the just-tapped card jump.
    /// Other cards are collapsed **only when a candidate is chosen via radio**.
    @State private var expandedOptions: Set<UUID> = []
    // Group expansion is keyed by claim id — keying by title would expand both when two cards share a name.
    @State private var expandedGroups: Set<UUID> = []
    /// Re-tap guard while submitting. The loading HUD is a PassThroughWindow and can't block touches, so lock at the screen level.
    /// (On paths where the screen stays after auth cancel, it is released after `onSubmit` completes so retry is possible.)
    @State private var isSubmitting: Bool = false

    private var institution: String { summary?.verifierName ?? "—" }
    private var isMulti: Bool { options.count > 1 }
    private var currentOption: VpOption? {
        options.first { $0.id == selectedOption } ?? options.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                // Same cancel path as the bottom Reject — locked together while submitting. In proximity presentation `reject()`
                // cuts off the in-flight `respond`.
                Button(action: onBack) {
                    Image(.icBack)
                        .renderingMode(.template)
                        .foregroundStyle(.white)
                        .padding()
                }
                .accessibilityIdentifier("backButton")
                .disabled(isSubmitting)
                Text("Presentation")
                    .font(.pretendard(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                Image(.icBack)
                    .padding()
                    .hidden()
            }
            .frame(height: 56)
            .background(Color.customPrimary.ignoresSafeArea(edges: .top))

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader(title: "Requesting Institution")
                        Text(institution)
                            .font(.pretendard(size: 14, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(.borderGray, lineWidth: 1)
                            )
                            .shadow(color: .primaryShadow.opacity(0.06), radius: 1.5, x: 0, y: 1)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader(title: "Submission Details")
                        VStack(spacing: 12) {
                            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                                if isMulti {
                                    optionCard(option, index: index)
                                } else {
                                    singleCard(option)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 20)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }

            // Reject(outline) / Accept(filled) 1:1. Reject is the same cancel path as the app-bar Back, so
            // it calls `onBack` directly without confirmation and is always enabled regardless of Accept's disabled state.
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Text("Reject")
                        .font(.pretendard(size: 16, weight: .semibold))
                        .foregroundStyle(.customPrimary)
                        .frame(height: 52)
                        .frame(maxWidth: .infinity)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.customPrimary, lineWidth: 1.5)
                        )
                }
                .accessibilityIdentifier("rejectButton")
                .disabled(isSubmitting)

                Button(action: submit) {
                    Text("Accept")
                        .font(.pretendard(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(height: 52)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(canSubmit
                                      ? Color.customPrimary
                                      : Color(red: 248/255, green: 215/255, blue: 184/255))
                        )
                        .shadow(color: canSubmit ? .customPrimary.opacity(0.3) : .clear,
                                radius: 3, x: 0, y: 2)
                }
                .accessibilityIdentifier("acceptButton")
                .disabled(!canSubmit || isSubmitting)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(
                Rectangle()
                    .fill(.backgroundGray)
                    .overlay(Rectangle().frame(height: 1).foregroundStyle(.borderGray), alignment: .top)
            )
        }
        .background(.backgroundGray)
        .onAppear(perform: buildOptions)
    }

    // MARK: - State

    /// summary → screen render model. Built once into @State for id stability.
    ///
    /// Initial state is opt-in — no checks (REQUIRED is not checkable), and with multiple candidates
    /// Option 1 is selected with **all cards collapsed**. Groups start expanded.
    private func buildOptions() {
        guard options.isEmpty else { return }
        options = (summary?.documents ?? []).map { doc in
            // REQUIRED comes only from top-level rows and propagates to the whole subtree — sections split by the top level.
            let rows = doc.claims.map { claim in
                (required: claim.required,
                 claim: VpClaim(code: claim.code,
                                label: claim.label,
                                value: claim.value,
                                descendantCodes: claim.children.compactMap(\.code),
                                children: claim.children.map {
                                    VpChildRow(label: $0.label, value: $0.value)
                                }))
            }
            return VpOption(
                credentialId: doc.credentialId,
                title: doc.title,
                requiredCodes: doc.requiredCodes,
                required: rows.filter(\.required).map(\.claim),
                optional: rows.filter { !$0.required }.map(\.claim)
            )
        }
        selectedOption = options.first?.id
        // With multiple candidates, start with all cards collapsed. With one, that card starts expanded.
        expandedOptions = options.count > 1 ? [] : Set(options.prefix(1).map(\.id))
        expandedGroups = Set(options.flatMap { $0.required + $0.optional }
            .filter(\.isGroup)
            .map(\.id))
    }

    /// Submit enabled = **at least one item to be submitted** in the selected option.
    /// Always enabled if there is any REQUIRED item; an OPTIONAL-only set needs at least one checked to be enabled.
    private var canSubmit: Bool {
        guard let option = currentOption else { return false }
        return !option.requiredCodes.isEmpty || !checked.isEmpty
    }

    /// Submit trigger — an in-flight guard blocks re-taps. `onSubmit` runs until auth and network finish
    /// (on success/failure the screen is replaced; on auth cancel this screen stays), so the guard is released afterwards.
    private func submit() {
        guard !isSubmitting, let option = currentOption else { return }
        isSubmitting = true
        Task {
            await onSubmit([option.credentialId: checked])
            isSubmitting = false
        }
    }

    /// Radio selection — moving to another candidate **resets all checks** of the previous option.
    /// Expands only the chosen card and **collapses the rest** — the only path that collapses other cards.
    /// Re-tapping an already-selected radio also expands it (checks are kept).
    private func select(_ option: VpOption) {
        withAnimation(Self.foldAnimation) {
            if selectedOption != option.id {
                selectedOption = option.id
                checked = []
            }
            expandedOptions = [option.id]
        }
    }

    /// Document header tap — opens/closes **only that card**. Other cards stay expanded.
    private func toggleExpand(_ option: VpOption) {
        withAnimation(Self.foldAnimation) {
            if expandedOptions.contains(option.id) {
                expandedOptions.remove(option.id)
            } else {
                expandedOptions.insert(option.id)
            }
        }
    }

    /// Collapse/expand animation.
    ///
    /// When a card above collapses, cards below shift by that much (measured 221pt). With all content fitting on screen
    /// there is **no scroll room**, so the shift can't be offset by scrolling — `ScrollViewProxy.scrollTo`
    /// does nothing when scroll offset is 0 (verified by measurement). So on the path where the shift remains
    /// (radio switch) we make it **not jump in a single frame**: the card slides into its new position.
    private static let foldAnimation: Animation = .easeInOut(duration: 0.22)


    /// Check toggle — one parent moves its whole subtree (`descendantCodes`).
    /// This function's contract: only what's shown goes out, and everything that goes out is shown.
    private func toggle(_ claim: VpClaim) {
        guard let code = claim.code else { return }
        if checked.contains(code) {
            checked.subtract(claim.toggledCodes)
        } else {
            checked.formUnion(claim.toggledCodes)
        }
    }

    /// Toggle all OPTIONAL. **No intermediate state** — if all are on, turn off; otherwise turn all on.
    private func toggleSelectAll(_ option: VpOption) {
        let codes = option.optionalCodes
        if codes.isSubset(of: checked) {
            checked.subtract(codes)
        } else {
            checked.formUnion(codes)
        }
    }

    // MARK: - Cards

    /// Single candidate — draw the claim list directly without a radio (26 · 26a · 26b).
    private func singleCard(_ option: VpOption) -> some View {
        let open = expandedOptions.contains(option.id)
        return VStack(spacing: 0) {
            documentHeader(option, open: open)
            if open {
                claimSections(option, selectable: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, open ? 12 : 4)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white)
                .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
        )
    }

    /// 2+ candidates — radio option cards (26c). Only the selected card shows checkboxes.
    private func optionCard(_ option: VpOption, index: Int) -> some View {
        let selected = selectedOption == option.id
        let open = expandedOptions.contains(option.id)
        return VStack(spacing: 0) {
            Button {
                select(option)
            } label: {
                HStack(spacing: 12) {
                    VpOptionRadio(on: selected)
                    Text("Option \(index + 1) of \(options.count)")
                        .font(.pretendard(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Color.paleOrange : .white)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("optionRadio")
            .buttonStyle(.plain)

            VStack(spacing: 0) {
                documentHeader(option, open: open)
                if open {
                    // Unselected options show label/value only — neither checkboxes nor Select all.
                    claimSections(option, selectable: selected)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .overlay(alignment: .top) {
                Rectangle().fill(.borderGray).frame(height: 1)
            }
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(selected ? Color.customPrimary : .borderGray,
                        lineWidth: selected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
    }

    private func documentHeader(_ option: VpOption, open: Bool) -> some View {
        Button {
            toggleExpand(option)
        } label: {
            HStack(spacing: 8) {
                Image(open ? .icChevU : .icChevD)
                Text(option.title)
                    .font(.pretendard(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("sectionChevron")
        .buttonStyle(.plain)
    }

    /// REQUIRED (top) → OPTIONAL (bottom). Only sections with content are drawn — no count badge or helper text.
    /// - parameter selectable: whether checkboxes and Select all are shown. false on unselected option cards.
    @ViewBuilder
    private func claimSections(_ option: VpOption, selectable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !option.required.isEmpty {
                VpSectionLabel(title: "Required", isFirst: true)
                // REQUIRED draws no checkboxes — these items can't be unchecked.
                claimRows(option.required, selectable: false)
            }
            if !option.optional.isEmpty {
                VpSectionLabel(title: "Optional", isFirst: option.required.isEmpty) {
                    if selectable {
                        VpSelectAll(allOn: !option.optionalCodes.isEmpty
                                    && option.optionalCodes.isSubset(of: checked)) {
                            toggleSelectAll(option)
                        }
                    }
                }
                claimRows(option.optional, selectable: selectable)
            }
        }
        .padding(.leading, 12)
    }

    @ViewBuilder
    private func claimRows(_ claims: [VpClaim], selectable: Bool) -> some View {
        ForEach(Array(claims.enumerated()), id: \.element.id) { index, claim in
            let isLast = index == claims.count - 1
            if claim.isGroup {
                VpClaimGroup(
                    title: claim.label,
                    children: claim.children,
                    checkbox: checkbox(for: claim, selectable: selectable),
                    isExpanded: expandedGroups.contains(claim.id),
                    isLast: isLast,
                    onToggleExpand: {
                        if expandedGroups.contains(claim.id) {
                            expandedGroups.remove(claim.id)
                        } else {
                            expandedGroups.insert(claim.id)
                        }
                    }
                )
            } else {
                VpClaimRow(
                    label: claim.label,
                    value: claim.value,
                    checkbox: checkbox(for: claim, selectable: selectable),
                    isLast: isLast
                )
            }
        }
    }

    /// Checkbox — nil where it can't be toggled, leaving the slot itself empty.
    /// (REQUIRED section · unselected option card · display-only row without a code.)
    private func checkbox(for claim: VpClaim, selectable: Bool) -> VpCheckbox? {
        guard selectable, let code = claim.code else { return nil }
        return VpCheckbox(checked: checked.contains(code)) { toggle(claim) }
    }
}

// MARK: - Subviews

/// Checkbox box only — the wrapper receives taps (a row checkbox is its own button; Select all is one button including its label).
/// The check glyph is drawn by the wrapper as an overlay (`VpCheckGlyph`).
private struct VpCheckboxMark: View {
    let checked: Bool
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size > 20 ? 6 : 5)
            .stroke(checked ? .customPrimary : .dotGray, lineWidth: 1.5)
            .fill(checked ? Color.customPrimary : .white)
            .frame(width: size, height: size)
    }
}

/// Check glyph over a checked box. Kept outside the button label so it stays its own accessibility element —
/// UI tests read the checked state from its presence (`checkIcon` / `selectAllCheckIcon`).
private struct VpCheckGlyph: View {
    let identifier: String

    var body: some View {
        Image(.icCheckSmall)
            .renderingMode(.template)
            .foregroundStyle(.white)
            .allowsHitTesting(false)
            .accessibilityIdentifier(identifier)
    }
}

/// Disclosure checkbox. Not attached at all where it can't be drawn (= can't be unchecked) — there is no lock indicator.
private struct VpCheckbox: View {
    let checked: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VpCheckboxMark(checked: checked)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("checkboxFrame")
        .overlay {
            if checked { VpCheckGlyph(identifier: "checkIcon") }
        }
    }
}

/// Radio — attached to the card header when there are 2+ candidates.
private struct VpOptionRadio: View {
    let on: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(on ? Color.customPrimary : .gray500, lineWidth: on ? 2 : 1.5)
                .frame(width: 20, height: 20)
            if on {
                Circle()
                    .fill(Color.customPrimary)
                    .frame(width: 10, height: 10)
            }
        }
    }
}

/// REQUIRED / OPTIONAL section label. No count or helper text.
private struct VpSectionLabel<Trailing: View>: View {
    let title: String
    let isFirst: Bool
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.pretendard(size: 11, weight: .bold))
                .kerning(0.6)
                .textCase(.uppercase)
                .foregroundStyle(.customGray)
            // Select all sits at the **right end of the row**, not beside the section label — aligned with the checkbox column below.
            Spacer(minLength: 0)
            trailing
        }
        .padding(.top, isFirst ? 8 : 14)
        .padding(.bottom, 4)
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle().fill(.borderGray).frame(height: 1)
            }
        }
    }
}

extension VpSectionLabel where Trailing == EmptyView {
    init(title: String, isFirst: Bool) {
        self.init(title: title, isFirst: isFirst, trailing: { EmptyView() })
    }
}

/// Toggle for the whole OPTIONAL section. No intermediate state is drawn — shown checked only when all are on.
private struct VpSelectAll: View {
    let allOn: Bool
    let onToggle: () -> Void

    var body: some View {
        // Label and checkbox are one button — tapping just the text toggles too (so the tap area exceeds 22dp).
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Text("Select all")
                    .font(.pretendard(size: 11, weight: .bold))
                    .foregroundStyle(.customPrimary)
                VpCheckboxMark(checked: allOn, size: 18)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("selectAllBox")
        .overlay(alignment: .trailing) {
            if allOn {
                VpCheckGlyph(identifier: "selectAllCheckIcon")
                    .frame(width: 18, height: 18)
            }
        }
    }
}

private struct VpClaimRow: View {
    let label: String
    let value: ClaimValue
    let checkbox: VpCheckbox?
    let isLast: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                // Label kept as-is — for SD-JWT this value is the claim key itself, so uppercasing would alter the data.
                // (For W3C it's the schema caption, but the detail screen already draws it as-is, so we match.)
                if !label.isEmpty {
                    Text(label)
                        .font(.pretendard(size: 11, weight: .medium))
                        .kerning(0.3)
                        .foregroundStyle(.customGray)
                }
                VpClaimValueView(value: value)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            checkbox
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(.borderGray).frame(height: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("claimRow")
    }
}

/// Claim value on the presentation screen — text or image. An image replaces the value text,
/// and the checkbox stays on the right. Same sizing rules as the detail screen, just a narrower available width.
private struct VpClaimValueView: View {
    let value: ClaimValue

    var body: some View {
        switch value {
        case .text(let text):
            Text(text)
                .font(.pretendard(size: 14, weight: .regular))
                .foregroundStyle(.black)
        case .image(let data):
            ClaimImageView(data: data)
                .padding(.top, 3)
        }
    }
}

/// Item with children — one parent checkbox toggles the whole subtree, and children are **display only**.
/// The checkbox tap and the expand toggle work independently.
private struct VpClaimGroup: View {
    let title: String
    let children: [VpChildRow]
    /// nil means a group that can't be checked — a REQUIRED group or an unselected option card.
    /// Only expand/collapse works.
    let checkbox: VpCheckbox?
    let isExpanded: Bool
    let isLast: Bool
    let onToggleExpand: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onToggleExpand) {
                    HStack(spacing: 6) {
                        Image(isExpanded ? .icChevU : .icChevD)
                        Text(title)
                            .font(.pretendard(size: 13, weight: .bold))
                            .foregroundStyle(.black)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                checkbox
            }
            .padding(.vertical, 12)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("claimRow")

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                        VpClaimRow(
                            // Child label = object key as-is. Array elements have an empty label and show only the value.
                            label: child.label,
                            value: child.value,
                            checkbox: nil,
                            isLast: index == children.count - 1
                        )
                    }
                }
                .padding(.leading, 12)
                .padding(.bottom, 6)
            }
        }
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(.borderGray).frame(height: 1)
            }
        }
    }
}

#Preview {
    VPRequestView()
}
