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

/// VC detail screen. For a ZKP-paired credential, additionally renders a "Zero-Knowledge Proof" section
/// — not a separate screen; one view branches on `credential.zkp`.
struct VCDetailView: View {
    let credential: Credential
    var onBack: () -> Void = {}
    var onConfirmDelete: () -> Void = {}
    /// Reports the status freshly fetched on entry to the outside — the list draws a snapshot made on entry,
    /// so without passing this along the latest status shows only in detail and the old badge remains after going back.
    var onStatusRefreshed: (CredentialStatus) -> Void = { _ in }

    @State private var expandedGroups: Set<String> = []
    // Status freshly fetched on entry. nil means not fetched yet → show credential.status.
    @State private var refreshedStatus: CredentialStatus?

    var body: some View {
        VStack(spacing: 0) {
            navBar

            // Below the nav bar — the area where the colored hero, card and claims scroll together.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CredentialHero(credential: credential, statusOverride: refreshedStatus)

                    VStack(alignment: .leading, spacing: 20) {
                        detailsSection

                        if credential.zkp {
                            zkpSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                }
                .background(alignment: .top) {
                    // Extend the hero color upward so the orange doesn't break off above the content
                    // when pulled down into overscroll (bounce).
                    Color.customPrimary
                        .frame(height: 1200)
                        .offset(y: -1200)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.backgroundGray)
        .task {
            let status = await CredentialStore.shared.refreshedStatus(for: credential)
            refreshedStatus = status
            onStatusRefreshed(status)
        }
    }

    // Back/trash — fixed nav bar at the top. The colored background extends behind the status bar.
    private var navBar: some View {
        HStack {
            Button(action: onBack) {
                Image(.icBackWhite)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Button(action: { showDeleteConfirmation(onConfirm: onConfirmDelete) }) {
                Image(.icDelete)
                    .renderingMode(.template)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 56)
        .frame(maxWidth: .infinity)
        .background(Color.customPrimary.ignoresSafeArea(edges: .top))
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Certificate Details")

            VStack(spacing: 0) {
                ForEach(Array(credential.claims.enumerated()), id: \.element.id) { idx, entry in
                    let isLast = idx == credential.claims.count - 1
                    switch entry.kind {
                    case .row(let label, let value):
                        ClaimRow(label: label, value: value, hasDivider: !isLast)
                    case .group(let title, let items):
                        ClaimGroup(
                            title: title,
                            items: items,
                            isExpanded: expandedGroups.contains(title),
                            hasDivider: !isLast,
                            onToggle: { toggleGroup(title) }
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
            )
        }
    }

    private var zkpSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Zero-Knowledge Proof", accent: .zkpAccent)

            VStack(spacing: 0) {
                ForEach(Array(credential.zkpClaims.enumerated()), id: \.element.id) { idx, item in
                    ClaimRow(
                        label: item.label,
                        value: item.value,
                        hasDivider: idx < credential.zkpClaims.count - 1
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.zkpBorder.opacity(0.14), lineWidth: 1)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
            )
        }
    }

    private func toggleGroup(_ title: String) {
        if expandedGroups.contains(title) {
            expandedGroups.remove(title)
        } else {
            expandedGroups.insert(title)
        }
    }
}

func showDeleteConfirmation(onConfirm: @escaping () -> Void) {
    OverlayManager.shared.showPopup(
        title: "Delete certificate?",
        message: "This certificate will be permanently deleted from your wallet and may affect your access to services.",
        primaryButtonTitle: "Delete",
        primaryAction: { onConfirm() },
        secondaryButtonTitle: "Cancel"
    )
}

struct ClaimRow: View {
    let label: String
    let value: ClaimValue
    var hasDivider: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The label is the raw claim key — no processing such as uppercasing.
            // An empty label is an array element (a row with no name to attach), so only the value is drawn.
            if !label.isEmpty {
                Text(label)
                    .font(.pretendard(size: 13, weight: .regular))
                    .foregroundStyle(.customGray)
            }

            valueView
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if hasDivider {
                Rectangle()
                    .fill(.borderGray)
                    .frame(height: 1)
            }
        }
    }

    // An image claim replaces the value text — the two are never shown together (VC-B-01).
    // Sizing rules (original size · no upscaling · no height cap) belong to `ClaimImageView`.
    @ViewBuilder
    private var valueView: some View {
        switch value {
        case .text(let text):
            Text(text)
                .font(.pretendard(size: 14, weight: .semibold))
                .foregroundStyle(.black)
        case .image(let data):
            ClaimImageView(data: data)
                .padding(.top, 4)
        }
    }
}

struct ClaimGroup: View {
    let title: String
    let items: [ClaimItem]
    let isExpanded: Bool
    var hasDivider: Bool = true
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Image(isExpanded ? .icChevU : .icChevD)
                        .renderingMode(.template)
                        .foregroundStyle(.customPrimary)
                        .frame(width: 18, height: 18)
                    // Group title = the SD-JWT disclosure's claim key — drawn as-is.
                    Text(title)
                        .font(.pretendard(size: 11, weight: .bold))
                        .kerning(0.4)
                        .foregroundStyle(.customGray)
                    Spacer()
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        ClaimRow(
                            label: item.label,
                            value: item.value,
                            hasDivider: idx < items.count - 1
                        )
                    }
                }
                .padding(.leading, 12)
                .padding(.bottom, 6)
            }
        }
        .overlay(alignment: .bottom) {
            if hasDivider {
                Rectangle()
                    .fill(.borderGray)
                    .frame(height: 1)
            }
        }
    }
}

#Preview {
    VCDetailView(credential: SampleCredentials.mdl)
}
