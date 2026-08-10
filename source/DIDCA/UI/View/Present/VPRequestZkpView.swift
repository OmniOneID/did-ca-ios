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

/// ZKP VP 제출 메인 화면. did-ca-ios `ZKPSubmissionViewController` 와 동일 구조 —
/// 한 화면에 Attributes / Predicates / Self-Attributes 세 그룹이 평탄하게 나열되고,
/// document 단위 accordion 으로 묶지 않는다 (proof 는 여러 VC 의 sub-referent 를 섞을 수
/// 있어 "한 VC = 한 카드" 매핑이 성립하지 않음).
struct VPRequestZkpView: View {
    var onBack: () -> Void = {}
    var onSubmit: () -> Void = {}
    /// attribute / predicate 행의 값(또는 "Tap to select >") 을 탭했을 때 picker 진입 — referent key 인자.
    var onSelectAttribute: (_ key: String) -> Void = { _ in }

    @Environment(AppCoordinator.self) private var coordinator

    private var summary: ZkpPresentationSummary {
        coordinator.zkpProto?.presentationSummary
            ?? ZkpPresentationSummary(verifierName: "", title: "", attributes: [], predicates: [], selfAttributes: [])
    }

    /// referent key 에 대해 사용자가 picker 로 고른 sub-referent 의 raw 값 (없으면 nil).
    private func selectedValue(for claim: ZkpPresentationClaim) -> String? {
        guard let idx = coordinator.zkpAttrSelections[claim.key],
              claim.availableValues.indices.contains(idx) else {
            return nil
        }
        return claim.availableValues[idx].raw
    }

    /// 모든 attribute / predicate 가 선택되고 모든 self-attribute 가 채워졌는지 — Submit 활성화 조건.
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

    private var submitBar: some View {
        VStack {
            Button(action: onSubmit) {
                Text("Submit")
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
        // did-ca-ios 와 동일: predicate 셀도 사용자가 picker 로 어느 VC 의 sub-referent 로 증명할지 선택,
        // 선택된 sub-referent 의 raw 값을 표시 (verifier 에는 raw 가 노출되지 않음 — 표시는 사용자 확인용).
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

/// label + value(또는 placeholder) + trailing(눈 토글 또는 EmptyView) — attribute / predicate
/// 행을 공유하는 픽커 행. did-ca-ios `ZKPSubmissionTableViewCell` 와 동일하게 한 cell 을
/// 두 섹션이 공유하며 trailing(눈 버튼) 만 표시/숨김으로 차이를 둔다.
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
                // 라벨은 원형 그대로 — caption 이 없으면 attribute 키 원문이 그대로 오므로
                // 대문자 변환은 데이터 변형이 된다. VP 제출·속성 선택·VC 상세와 표기를 맞춘다.
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

/// self-attribute 입력 행 — label + 텍스트필드. did-ca-ios `ZKPSubmissionTextTableViewCell` 와 등가.
private struct ZkpSelfAttrRow: View {
    let label: String
    @Binding var text: String
    let isLast: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 라벨 원형 유지 — ZkpPickerRow 주석 참조.
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
