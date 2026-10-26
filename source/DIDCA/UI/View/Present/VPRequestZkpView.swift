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

/// Main ZKP VP submission screen. Same structure as did-ca-ios `ZKPSubmissionViewController` —
/// the three groups Attributes / Predicates / Self-Attributes are listed flat on one screen,
/// not grouped into per-document accordions (a proof can mix sub-referents from multiple VCs,
/// so a "one VC = one card" mapping doesn't hold).
struct VPRequestZkpView: View {
    var onBack: () -> Void = {}
    var onSubmit: () -> Void = {}
    /// Enters the picker when an attribute / predicate row's value (or "Tap to select >") is tapped — argument is the referent key.
    var onSelectAttribute: (_ key: String) -> Void = { _ in }

    @Environment(AppCoordinator.self) private var coordinator

    private var summary: ZkpPresentationSummary {
        coordinator.zkpProto?.presentationSummary
            ?? ZkpPresentationSummary(verifierName: "", title: "", attributes: [], predicates: [], selfAttributes: [])
    }

    /// Raw value of the sub-referent the user picked for the referent key (nil if none).
    private func selectedValue(for claim: ZkpPresentationClaim) -> String? {
        guard let idx = coordinator.zkpAttrSelections[claim.key],
              claim.availableValues.indices.contains(idx) else {
            return nil
        }
        return claim.availableValues[idx].raw
    }

    /// Whether every attribute / predicate is selected and every self-attribute filled — the Accept enable condition.
    private var canSubmit: Bool {
        for claim in summary.attributes {
            if coordinator.zkpAttrSelections[claim.key] == nil { return false }
        }
        for claim in summary.predicates {
            if coordinator.zkpAttrSelections[claim.key] == nil { return false }
        }
        for claim in summary.selfAttributes {
            if (coordinator.zkpSelfRaws[claim.key] ?? "").isEmpty { return false }
        }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            navigationBar

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    requestingInstitutionCard
                    submissionDetails
                }
                .padding(.top, 20)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }

            submitBar
        }
        .background(.backgroundGray)
    }

    private var navigationBar: some View {
        HStack {
            Button(action: onBack) {
                Image(.icBack)
                    .renderingMode(.template)
                    .foregroundStyle(.white)
                    .padding()
            }
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
    }

    private var requestingInstitutionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Requesting Institution")
            Text(summary.verifierName)
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
    }

    @ViewBuilder
    private var submissionDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Submission Details")
            VStack(spacing: 12) {
                if !summary.attributes.isEmpty {
                    groupCard(title: "Attributes") {
                        ForEach(Array(summary.attributes.enumerated()), id: \.offset) { idx, claim in
                            attributeRow(
                                claim: claim,
                                isLast: idx == summary.attributes.count - 1
                            )
                        }
                    }
                }
                if !summary.predicates.isEmpty {
                    groupCard(title: "Predicates") {
                        ForEach(Array(summary.predicates.enumerated()), id: \.offset) { idx, claim in
                            predicateRow(
                                claim: claim,
                                isLast: idx == summary.predicates.count - 1
                            )
                        }
                    }
                }
                if !summary.selfAttributes.isEmpty {
                    groupCard(title: "Self-Attributes") {
                        ForEach(Array(summary.selfAttributes.enumerated()), id: \.offset) { idx, claim in
                            selfAttrRow(
                                claim: claim,
                                isLast: idx == summary.selfAttributes.count - 1
                            )
                        }
                    }
                }
            }
        }
    }

    /// PRES-B-12 — same Reject / Accept layout as the SD screen (VPRequestView). Reject is the same cancel path as Back.
    private var submitBar: some View {
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

            Button(action: onSubmit) {
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
            .disabled(!canSubmit)
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

    @ViewBuilder
    private func groupCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.pretendard(size: 13, weight: .bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
            VStack(spacing: 0) { content() }
                .padding(.leading, 12)
                .padding(.bottom, 6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white)
                .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
        )
    }

    private func attributeRow(claim: ZkpPresentationClaim, isLast: Bool) -> some View {
        let value = selectedValue(for: claim)
        let revealed = coordinator.zkpReveals.contains(claim.key)
        return ZkpPickerRow(
            label: claim.label,
            value: value ?? "Tap to select >",
            valueIsPlaceholder: value == nil,
            isLast: isLast,
            trailing: {
                Button {
                    if revealed { coordinator.zkpReveals.remove(claim.key) }
                    else        { coordinator.zkpReveals.insert(claim.key) }
                } label: {
                    Image(revealed ? .icEye : .icEyeOff)
                        .renderingMode(.template)
                        .foregroundStyle(revealed ? Color.customPrimary : .gray500)
                        .padding(4)
                }
                .buttonStyle(.plain)
            },
            onValueTap: { onSelectAttribute(claim.key) }
        )
    }

    private func predicateRow(claim: ZkpPresentationClaim, isLast: Bool) -> some View {
        // Same as did-ca-ios: for predicate cells the user also picks which VC's sub-referent to prove with,
        // and the selected sub-referent's raw value is shown (raw is not exposed to the verifier — display is for user confirmation).
        let value = selectedValue(for: claim)
        return ZkpPickerRow(
            label: claim.label,
            value: value ?? "Tap to select >",
            valueIsPlaceholder: value == nil,
            isLast: isLast,
            trailing: { EmptyView() },
            onValueTap: { onSelectAttribute(claim.key) }
        )
    }

    private func selfAttrRow(claim: ZkpPresentationClaim, isLast: Bool) -> some View {
        ZkpSelfAttrRow(
            label: claim.label,
            text: Binding(
                get: { coordinator.zkpSelfRaws[claim.key] ?? "" },
                set: { coordinator.zkpSelfRaws[claim.key] = $0 }
            ),
            isLast: isLast
        )
    }
}

/// label + value (or placeholder) + trailing (eye toggle or EmptyView) — picker row shared by attribute / predicate
/// rows. Like did-ca-ios `ZKPSubmissionTableViewCell`, one cell is shared by
/// both sections, differing only in whether trailing (eye button) is shown or hidden.
private struct ZkpPickerRow<Trailing: View>: View {
    let label: String
    let value: String
    var valueIsPlaceholder: Bool = false
    let isLast: Bool
    @ViewBuilder var trailing: () -> Trailing
    var onValueTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                // Label kept as-is — without a caption the raw attribute key comes through,
                // so uppercasing would alter the data. Matches VP submission, attribute selection and VC detail.
                Text(label)
                    .font(.pretendard(size: 11, weight: .medium))
                    .kerning(0.5)
                    .foregroundStyle(.customGray)

                Button(action: onValueTap) {
                    Text(value)
                        .font(.pretendard(size: 14, weight: .regular))
                        .foregroundStyle(valueIsPlaceholder ? .customPrimary : .black)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(.borderGray).frame(height: 1)
            }
        }
    }
}

/// self-attribute input row — label + text field. Equivalent to did-ca-ios `ZKPSubmissionTextTableViewCell`.
private struct ZkpSelfAttrRow: View {
    let label: String
    @Binding var text: String
    let isLast: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Keep the label as-is — see the ZkpPickerRow comment.
            Text(label)
                .font(.pretendard(size: 11, weight: .medium))
                .kerning(0.5)
                .foregroundStyle(.customGray)

            TextField("Enter value", text: $text)
                .font(.pretendard(size: 14, weight: .regular))
                .foregroundStyle(.black)
                .textFieldStyle(.plain)
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(.borderGray).frame(height: 1)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(.borderGray).frame(height: 1)
            }
        }
    }
}

#Preview {
    VPRequestZkpView()
        .environment(AppCoordinator())
}
