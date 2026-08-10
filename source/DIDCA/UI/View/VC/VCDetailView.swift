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

/// VC 상세화면. ZKP 페어 크레덴셜이면 "Zero-Knowledge Proof" 섹션을
/// 추가로 렌더 — 별도 화면이 아니라 한 뷰가 `credential.zkp` 로 분기한다.
struct VCDetailView: View {
    let credential: Credential
    var onBack: () -> Void = {}
    var onConfirmDelete: () -> Void = {}
    /// 진입 시 새로 조회한 상태를 밖으로 알린다 — 목록은 진입 때 만든 스냅샷을 그리므로,
    /// 이걸 흘려보내지 않으면 상세에서만 최신 상태가 보이고 뒤로 나오면 옛 뱃지가 남는다.
    var onStatusRefreshed: (CredentialStatus) -> Void = { _ in }

    @State private var expandedGroups: Set<String> = []
    // 진입 시 새로 조회한 상태. nil 이면 아직 미조회 → credential.status 표시.
    @State private var refreshedStatus: CredentialStatus?

    var body: some View {
        VStack(spacing: 0) {
            navBar

            // 네비바 아래 — 컬러 히어로·카드·클레임이 함께 스크롤되는 영역.
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
                    // 위로 당겨 오버스크롤(바운스)할 때 콘텐츠 위 영역까지
                    // 주황색이 끊기지 않도록 히어로 컬러를 위로 연장한다.
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

    // 백/휴지통 — 상단 고정 네비바. 컬러 배경이 상태바 뒤까지 확장된다.
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
            // 라벨은 클레임 키 원형 그대로 — 대문자 변환 등 가공을 하지 않는다.
            // 빈 라벨은 배열 원소(붙일 이름이 없는 행)라 값만 그린다.
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

    // 이미지 클레임은 원본 비율을 유지(scaledToFit)한 채 폭에 맞춰 표시한다.
    @ViewBuilder
    private var valueView: some View {
        switch value {
        case .text(let text):
            Text(text)
                .font(.pretendard(size: 14, weight: .semibold))
                .foregroundStyle(.black)
        case .image(let data):
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 180, alignment: .leading)
            } else {
                Text("—")
                    .font(.pretendard(size: 14, weight: .semibold))
                    .foregroundStyle(.customGray)
            }
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
                    // 그룹 제목 = SD-JWT disclosure 의 클레임 키 — 원형 그대로 그린다.
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
