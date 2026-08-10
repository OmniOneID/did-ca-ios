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

struct VpClaim: Identifiable {
    enum Kind {
        case row(code: String, label: String, value: String, locked: Bool)
        // SD-JWT 복합값(object/array) disclosure — disclosure 는 원자 단위라 상위 `code` 하나로
        // 통째 토글하고, 하위 `items` 는 표시 전용(개별 토글 없음).
        case group(code: String, title: String, locked: Bool, items: [(label: String, value: String)])
    }
    let id = UUID()
    let kind: Kind
}

struct VpDocument: Identifiable {
    let id = UUID()
    let credentialId: String
    let title: String
    let claims: [VpClaim]
}

/// VP 요청(제시) 화면. 검증자·제출 클레임은 `VpPresentationSummary`(VerifyVcProtocol 이 생성)에서 온다.
struct VPRequestView: View {
    var summary: VpPresentationSummary?
    var onBack: () -> Void = {}
    /// 사용자가 체크한 claim — credentialId → code 집합.
    ///
    /// 화면에 뜬 문서는 **빠짐없이** 담는다. 체크가 하나도 없으면 빈 집합으로 담아 "이 카드는 안 낸다"를
    /// 표현한다 — 키를 생략해 뜻을 싣던 예전 방식은 받는 쪽마다 다르게 읽혀(누락 = 전부 / 누락 = 없음)
    /// 제출 집합이 뒤집혔다. 잠금 항목도 사용자에게 제출된다고 표시했으므로 포함한다.
    var onSubmit: ([String: Set<String>]) async -> Void = { _ in }

    @State private var documents: [VpDocument] = []
    /// credentialId → 사용자가 체크한 claim code 집합 = 공개에 동의한 집합. 그대로 `onSubmit` 으로 나간다.
    ///
    /// 진입 시 노출된 code 전부(잠금 포함)로 채운다 — 잠금 항목도 화면에 체크로 보이고 실제로
    /// 제출되므로 빠지면 표시와 제출이 어긋난다. 그룹(복합값 disclosure)은 code 를 갖는 상위 항목만
    /// 담긴다(하위 행은 표시 전용, code 없음).
    ///
    /// 화면에 뜬 문서는 체크가 하나도 없더라도 **빈 집합으로 키가 남는다**. 받는 쪽은 "키 없음"을
    /// 해석할 필요 없이 집합만 보면 되고, 빈 집합은 곧 "이 카드는 제출하지 않는다"다.
    @State private var selected: [String: Set<String>] = [:]
    @State private var expandedDocs: Set<UUID> = []
    @State private var expandedGroups: Set<String> = []
    @State private var warned: Bool = false
    /// 제출 진행 중 재탭 가드. 로딩 HUD 는 PassThroughWindow 라 터치를 못 막으므로 화면단에서 잠근다.
    /// (인증 취소로 화면이 남는 경로에선 `onSubmit` 완료 후 풀려 재시도 가능.)
    @State private var isSubmitting: Bool = false

    private var institution: String { summary?.verifierName ?? "—" }

    var body: some View {
        VStack(spacing: 0) {
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
                            ForEach(documents) { doc in
                                documentCard(doc)
                            }
                        }
                    }
                }
                .padding(.top, 20)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }

            VStack {
                Button(action: submit) {
                    Text("Submit")
                        .font(.pretendard(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(height: 52)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(hasAnyChecked
                                      ? Color.customPrimary
                                      : Color(red: 248/255, green: 215/255, blue: 184/255))
                        )
                        .shadow(color: hasAnyChecked ? .customPrimary.opacity(0.3) : .clear,
                                radius: 3, x: 0, y: 2)
                }
                .disabled(!hasAnyChecked || isSubmitting)
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
        .onAppear(perform: buildDocuments)
    }

    /// 제출 트리거 — in-flight 가드로 재탭을 막는다. `onSubmit` 은 인증·네트워크가 끝날 때까지
    /// 이어지므로(성공/실패 시 화면이 교체되고, 인증 취소 시엔 이 화면이 남아) 완료 후 가드를 푼다.
    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task {
            await onSubmit(selected)
            isSubmitting = false
        }
    }

    // summary → 화면 렌더 모델. id 안정성을 위해 @State 에 한 번만 빌드한다.
    // 노출된 claim 은 전부 체크된 상태로 시작하므로 `selected` 도 같은 패스에서 채운다.
    private func buildDocuments() {
        guard documents.isEmpty else { return }
        documents = (summary?.documents ?? []).map { doc in
            let claims = doc.claims.map { claim -> VpClaim in
                // 하위 항목(SD-JWT 복합값)이 있으면 접이식 그룹, 없으면 단일 행.
                if !claim.children.isEmpty {
                    let items = claim.children.map { (label: $0.label, value: $0.value) }
                    return VpClaim(kind: .group(
                        code: claim.code, title: claim.label, locked: claim.locked, items: items))
                }
                return VpClaim(kind: .row(
                    code: claim.code,
                    label: claim.label,
                    value: claim.value,
                    locked: claim.locked
                ))
            }
            return VpDocument(
                credentialId: doc.credentialId,
                title: doc.title,
                claims: claims
            )
        }
        // 같은 credentialId 로 카드가 둘 이상 나오더라도 한 키에 합쳐진다 — 토글 상태가
        // credentialId 로 묶이는 건 렌더 이후 전 구간에서 동일하다.
        var initial: [String: Set<String>] = [:]
        for doc in documents {
            initial[doc.credentialId, default: []].formUnion(collectAllCodes(in: doc.claims))
        }
        selected = initial
        expandedDocs = Set(documents.map(\.id))
    }

    /// 화면 전체에서 체크된 claim 이 1개 이상이면 Submit 활성.
    /// 잠금 항목은 해제할 수 없으므로, 잠금이 하나라도 있는 화면에서는 항상 활성이다.
    private var hasAnyChecked: Bool {
        selected.values.contains { !$0.isEmpty }
    }

    private func collectAllCodes(in claims: [VpClaim]) -> [String] {
        claims.flatMap { claim -> [String] in
            switch claim.kind {
            case .row(let code, _, _, _):
                return [code]
            case .group(let code, _, _, _):
                return [code]
            }
        }
    }

    private func documentCard(_ doc: VpDocument) -> some View {
        let open = expandedDocs.contains(doc.id)
        return VStack(spacing: 0) {
            Button {
                if open { expandedDocs.remove(doc.id) } else { expandedDocs.insert(doc.id) }
            } label: {
                HStack(spacing: 6) {
                    Image(open ? .icChevU : .icChevD)
                    Text(doc.title)
                        .font(.pretendard(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                VStack(spacing: 0) {
                    ForEach(Array(doc.claims.enumerated()), id: \.element.id) { idx, claim in
                        let isLast = idx == doc.claims.count - 1
                        switch claim.kind {
                        case .row(let code, let label, let value, let locked):
                            VpClaimRow(
                                label: label,
                                value: value,
                                checked: selected[doc.credentialId]?.contains(code) ?? false,
                                isLocked: locked,
                                isLast: isLast,
                                onToggle: { toggle(credentialId: doc.credentialId, code: code) }
                            )
                        case .group(let code, let title, let locked, let items):
                            VpClaimGroup(
                                title: title,
                                items: items,
                                checked: selected[doc.credentialId]?.contains(code) ?? false,
                                isLocked: locked,
                                isExpanded: expandedGroups.contains(title),
                                isLast: isLast,
                                onToggleExpand: {
                                    if expandedGroups.contains(title) {
                                        expandedGroups.remove(title)
                                    } else {
                                        expandedGroups.insert(title)
                                    }
                                },
                                onToggle: { toggle(credentialId: doc.credentialId, code: code) }
                            )
                        }
                    }
                }
                .padding(.leading, 12)
                .padding(.bottom, 12)
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

    private func toggle(credentialId: String, code: String) {
        var on = selected[credentialId] ?? []
        if on.contains(code) {
            on.remove(code)
            if !warned {
                warned = true
                OverlayManager.shared.showPopup(
                    title: "Warning",
                    message: "Not sharing certain data may cause the requested credential issuance to fail.",
                    primaryButtonTitle: "Got it"
                )
            }
        } else {
            on.insert(code)
        }
        selected[credentialId] = on
    }
}

private struct VpClaimRow: View {
    let label: String
    let value: String
    let checked: Bool
    let isLocked: Bool
    let isLast: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                // 라벨은 원형 그대로 — SD-JWT 는 이 값이 곧 클레임 키라 대문자 변환이 데이터 변형이 된다.
                // (W3C 는 스키마 caption 이지만 상세화면이 이미 원형으로 그려 표기를 맞춘다.)
                if !label.isEmpty {
                    Text(label)
                        .font(.pretendard(size: 11, weight: .medium))
                        .kerning(0.3)
                        .foregroundStyle(.customGray)
                }
                Text(value)
                    .font(.pretendard(size: 14, weight: .regular))
                    .foregroundStyle(.black)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: { if !isLocked { onToggle() } }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isLocked ? .gray400 : (checked ? .customPrimary : .dotGray), lineWidth: 1.5)
                        .fill(isLocked ? Color.gray400 : (checked ? Color.customPrimary : .white))
                        .frame(width: 22, height: 22)

                    if checked {
                        Image(.icCheckSmall)
                            .renderingMode(.template)
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            // .disabled 를 쓰면 안 된다 — 비활성 버튼의 레이블은 SwiftUI 가 흐리게 그려서
            // 템플릿 이미지에 준 .foregroundStyle(.white) 가 먹지 않고 체크마크가 회색으로 보인다.
            // 탭만 막으면 충분하다(액션 자체도 isLocked 를 다시 확인한다).
            .allowsHitTesting(!isLocked)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(.borderGray).frame(height: 1)
            }
        }
    }
}

/// SD-JWT 복합값(object/array) disclosure — 상위 체크박스로 disclosure 를 통째 토글하고,
/// 하위 항목(items)은 표시 전용. (disclosure 는 원자 단위라 하위만 따로 공개할 수 없음.)
private struct VpClaimGroup: View {
    let title: String
    let items: [(label: String, value: String)]
    let checked: Bool
    let isLocked: Bool
    let isExpanded: Bool
    let isLast: Bool
    let onToggleExpand: () -> Void
    let onToggle: () -> Void

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

                Button(action: { if !isLocked { onToggle() } }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isLocked ? .gray400 : (checked ? .customPrimary : .dotGray), lineWidth: 1.5)
                            .fill(isLocked ? Color.gray400 : (checked ? Color.customPrimary : .white))
                            .frame(width: 22, height: 22)
                        if checked {
                            Image(.icCheckSmall)
                                .renderingMode(.template)
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                // .disabled 금지 — 이유는 VpClaimRow 주석 참조.
                .allowsHitTesting(!isLocked)
            }
            .padding(.vertical, 12)

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                        VStack(alignment: .leading, spacing: 3) {
                            // 하위 항목 라벨 = object 키 원형. 배열 원소는 라벨이 비어 값만 그린다.
                            if !item.label.isEmpty {
                                Text(item.label)
                                    .font(.pretendard(size: 11, weight: .medium))
                                    .kerning(0.3)
                                    .foregroundStyle(.customGray)
                            }
                            Text(item.value)
                                .font(.pretendard(size: 14, weight: .regular))
                                .foregroundStyle(.black)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            if idx != items.count - 1 {
                                Rectangle().fill(.borderGray).frame(height: 1)
                            }
                        }
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
