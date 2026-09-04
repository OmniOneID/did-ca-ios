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

/// 그룹(복합값 disclosure·mDoc 복합 원소)의 하위 한 줄 — **표시 전용**이다.
/// 하위는 개별 체크박스를 갖지 않는다(PRES-B-03). 제출 여부는 상위 체크박스 하나가 정하고,
/// 하위 code 는 상위의 `descendantCodes` 로만 따라 움직인다.
struct VpChildRow: Identifiable {
    let id = UUID()
    let label: String
    let value: ClaimValue
}

/// 한 행 = 제출 단위 하나. 하위가 있으면 접이식 그룹으로 그린다(한 단계만).
struct VpClaim: Identifiable {
    let id = UUID()
    /// 제출에 나가는 claim code. `nil` 이면 따로 뺄 수단이 없는 표시 전용 행이라 체크박스를 그리지 않는다.
    let code: String?
    let label: String
    let value: ClaimValue
    /// 이 행을 켜고 끌 때 **함께** 움직이는 하위 code — all-or-nothing(PRES-B-03).
    ///
    /// SD-JWT 하위 disclosure 는 자신을 가리는 조상 disclosure 를 항상 동반한다
    /// (SDK `SDJWTPresenter.resolveDisclosures`). 상·하위를 따로 놀게 두면 화면과 제출이 갈린다.
    let descendantCodes: [String]
    let children: [VpChildRow]

    var isGroup: Bool { !children.isEmpty }
    /// 체크가 이 행을 켜고 끌 때 건드리는 code 전부.
    var toggledCodes: Set<String> {
        guard let code else { return [] }
        return Set([code] + descendantCodes)
    }
}

/// 제출 후보 한 건 = 카드 한 장. 후보가 2건 이상이면 라디오 옵션 카드가 되고 **그중 1건만 제출된다**
/// (PRES-B-05).
struct VpOption: Identifiable {
    let id = UUID()
    let credentialId: String
    let title: String
    /// 체크와 무관하게 항상 제출되는 code. 비어 있지 않으면 Submit 은 항상 활성이다(PRES-E-05).
    let requiredCodes: Set<String>
    /// REQUIRED 섹션 — 체크박스를 그리지 않는다(회색 비활성 체크박스를 쓰지 않는다, PRES-B-02).
    let required: [VpClaim]
    /// OPTIONAL 섹션 — **해제 상태로 시작**한다(opt-in).
    let optional: [VpClaim]

    /// Select all 이 다루는 code — 표시 전용 행은 제외한다.
    var optionalCodes: Set<String> {
        optional.reduce(into: Set<String>()) { $0.formUnion($1.toggledCodes) }
    }
}

/// VP 요청(제시) 화면. 검증자·후보 목록은 `VpPresentationSummary` 에서 온다
/// (일반 VP = `VerifyVcProtocol`, OID4VP = `OID4VPPresenter` — 같은 타입, 같은 화면).
struct VPRequestView: View {
    var summary: VpPresentationSummary?
    var onBack: () -> Void = {}
    /// 제출 payload — **선택된 후보 1건만** 담는다(credentialId → 체크한 code).
    ///
    /// 고르지 않은 후보는 키 자체가 없다. 받는 쪽(`VerifyVcProtocol.submit` ·
    /// `OID4VPPresenter.applyConsent`)이 "키 없음 = 제출 대상 아님"으로 읽고 드롭한다.
    /// 체크가 0건이어도 REQUIRED 가 있으면 제출되므로, 빈 집합이 곧 "안 낸다"는 뜻은 아니다.
    var onSubmit: ([String: Set<String>]) async -> Void = { _ in }

    @State private var options: [VpOption] = []
    /// 라디오로 고른 후보. 후보가 1건이면 그 1건이 늘 선택 상태다.
    @State private var selectedOption: UUID?
    /// 선택된 후보에서 사용자가 켠 code. 후보를 바꾸면 통째로 비운다(PRES-B-05).
    @State private var checked: Set<String> = []
    /// 펼친 카드들 — **여러 장이 동시에 펼쳐질 수 있다**.
    ///
    /// 문서 헤더 탭은 그 카드만 여닫고 다른 카드를 건드리지 않는다 — 후보를 나란히 펼쳐 놓고
    /// 비교할 수 있어야 하고, 위 카드가 접히면 방금 누른 카드가 그만큼 튀기 때문이다.
    /// 다른 카드를 접는 것은 **라디오로 후보를 고를 때뿐**이다(설계서 PRES-B-05).
    @State private var expandedOptions: Set<UUID> = []
    // 그룹 펼침은 claim 의 id 로 잡는다 — 제목으로 잡으면 같은 이름이 두 카드에 있을 때 함께 펼쳐진다.
    @State private var expandedGroups: Set<UUID> = []
    /// 제출 진행 중 재탭 가드. 로딩 HUD 는 PassThroughWindow 라 터치를 못 막으므로 화면단에서 잠근다.
    /// (인증 취소로 화면이 남는 경로에선 `onSubmit` 완료 후 풀려 재시도 가능.)
    @State private var isSubmitting: Bool = false

    private var institution: String { summary?.verifierName ?? "—" }
    private var isMulti: Bool { options.count > 1 }
    private var currentOption: VpOption? {
        options.first { $0.id == selectedOption } ?? options.first
    }

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

            VStack {
                Button(action: submit) {
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

    // MARK: - 상태

    /// summary → 화면 렌더 모델. id 안정성을 위해 @State 에 한 번만 빌드한다.
    ///
    /// 진입 상태는 opt-in 이다 — 체크는 비었고(REQUIRED 는 체크 대상이 아니다), 후보가 여럿이면
    /// Option 1 이 선택된 채 **전 카드가 접혀** 있다(PRES-B-05). 그룹은 펼친 채로 시작한다.
    private func buildOptions() {
        guard options.isEmpty else { return }
        options = (summary?.documents ?? []).map { doc in
            // REQUIRED 는 상위 행에서만 내려오고 서브트리 전체로 전파된다 — 섹션 분리는 상위 기준이다.
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
        // 후보가 여럿이면 전 카드 접힘으로 시작한다(PRES-B-05). 1건이면 그 카드는 펼친 채로.
        expandedOptions = options.count > 1 ? [] : Set(options.prefix(1).map(\.id))
        expandedGroups = Set(options.flatMap { $0.required + $0.optional }
            .filter(\.isGroup)
            .map(\.id))
    }

    /// Submit 활성 = 선택된 옵션에서 **제출될 항목이 1건 이상**.
    /// REQUIRED 가 하나라도 있으면 항상 활성이고, OPTIONAL 만 있는 구성은 1건 이상 켜야 활성이다
    /// (PRES-E-05).
    private var canSubmit: Bool {
        guard let option = currentOption else { return false }
        return !option.requiredCodes.isEmpty || !checked.isEmpty
    }

    /// 제출 트리거 — in-flight 가드로 재탭을 막는다. `onSubmit` 은 인증·네트워크가 끝날 때까지
    /// 이어지므로(성공/실패 시 화면이 교체되고, 인증 취소 시엔 이 화면이 남아) 완료 후 가드를 푼다.
    private func submit() {
        guard !isSubmitting, let option = currentOption else { return }
        isSubmitting = true
        Task {
            await onSubmit([option.credentialId: checked])
            isSubmitting = false
        }
    }

    /// 라디오 선택 — 다른 후보로 옮기면 직전 옵션의 체크를 **전부 초기화**한다(PRES-B-05).
    /// 고른 카드만 펼치고 **나머지는 접는다** — 다른 카드를 접는 유일한 경로다.
    /// 이미 선택된 라디오를 다시 탭해도 펼쳐진다(체크는 유지).
    private func select(_ option: VpOption) {
        withAnimation(Self.foldAnimation) {
            if selectedOption != option.id {
                selectedOption = option.id
                checked = []
            }
            expandedOptions = [option.id]
        }
    }

    /// 문서 헤더 탭 — **그 카드만** 여닫는다. 다른 카드는 펼쳐진 채로 둔다.
    private func toggleExpand(_ option: VpOption) {
        withAnimation(Self.foldAnimation) {
            if expandedOptions.contains(option.id) {
                expandedOptions.remove(option.id)
            } else {
                expandedOptions.insert(option.id)
            }
        }
    }

    /// 접힘·펼침 애니메이션.
    ///
    /// 위 카드가 접히면 아래 카드는 그만큼 자리를 옮긴다(실측 221pt). 화면에 콘텐츠가 다 들어와
    /// **스크롤 여지가 없어** 그 이동을 스크롤로 상쇄할 수단이 없다 — `ScrollViewProxy.scrollTo` 는
    /// 스크롤이 0인 상태에서 아무 일도 하지 않는다(실측으로 확인). 그래서 이동이 남는 경로
    /// (라디오 전환)에서는 **한 프레임에 튀지 않게** 한다: 카드가 미끄러지듯 새 자리에 놓인다.
    private static let foldAnimation: Animation = .easeInOut(duration: 0.22)


    /// 체크 토글 — 상위 하나가 서브트리 전체를 움직인다(`descendantCodes`).
    /// 화면에 적힌 것만 나가고, 나가는 것은 모두 화면에 적혀 있게 하는 것이 이 함수의 계약이다.
    private func toggle(_ claim: VpClaim) {
        guard let code = claim.code else { return }
        if checked.contains(code) {
            checked.subtract(claim.toggledCodes)
        } else {
            checked.formUnion(claim.toggledCodes)
        }
    }

    /// OPTIONAL 전체 토글. **중간 상태가 없다** — 전부 켜져 있으면 끄고, 아니면 전부 켠다.
    private func toggleSelectAll(_ option: VpOption) {
        let codes = option.optionalCodes
        if codes.isSubset(of: checked) {
            checked.subtract(codes)
        } else {
            checked.formUnion(codes)
        }
    }

    // MARK: - 카드

    /// 후보 1건 — 라디오 없이 클레임 목록을 바로 그린다(26 · 26a · 26b).
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

    /// 후보 2건 이상 — 라디오 옵션 카드(26c). 선택된 카드만 체크박스를 노출한다.
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
            .buttonStyle(.plain)

            VStack(spacing: 0) {
                documentHeader(option, open: open)
                if open {
                    // 미선택 옵션은 라벨·값만 — 체크박스도 Select all 도 노출하지 않는다.
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
        .buttonStyle(.plain)
    }

    /// REQUIRED(상단) → OPTIONAL(하단). 내용이 있는 섹션만 그린다 — 개수 배지·보조 문구는 없다.
    /// - parameter selectable: 체크박스·Select all 노출 여부. 미선택 옵션 카드에서는 false 다.
    @ViewBuilder
    private func claimSections(_ option: VpOption, selectable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !option.required.isEmpty {
                VpSectionLabel(title: "Required", isFirst: true)
                // REQUIRED 는 체크박스를 그리지 않는다 — 해제할 수 없는 항목이다(PRES-B-02).
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

    /// 체크박스 — 켤 수 없는 자리에서는 nil 이라 자리 자체가 비워진다.
    /// (REQUIRED 섹션 · 미선택 옵션 카드 · code 없는 표시 전용 행.)
    private func checkbox(for claim: VpClaim, selectable: Bool) -> VpCheckbox? {
        guard selectable, let code = claim.code else { return nil }
        return VpCheckbox(checked: checked.contains(code)) { toggle(claim) }
    }
}

// MARK: - 하위 뷰

/// 체크박스 그림만 — 탭은 감싸는 쪽이 받는다(행 체크박스는 자기 버튼, Select all 은 라벨까지 한 버튼).
private struct VpCheckboxMark: View {
    let checked: Bool
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size > 20 ? 6 : 5)
                .stroke(checked ? .customPrimary : .dotGray, lineWidth: 1.5)
                .fill(checked ? Color.customPrimary : .white)
                .frame(width: size, height: size)

            if checked {
                Image(.icCheckSmall)
                    .renderingMode(.template)
                    .foregroundStyle(.white)
            }
        }
    }
}

/// 공개 여부 체크박스. 그릴 수 없는(=해제할 수 없는) 자리에는 아예 붙지 않는다 — 잠금 표현은 없다.
private struct VpCheckbox: View {
    let checked: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VpCheckboxMark(checked: checked)
        }
        .buttonStyle(.plain)
    }
}

/// 라디오 — 후보가 2건 이상일 때 카드 헤더에 붙는다(PRES-B-05).
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

/// REQUIRED / OPTIONAL 섹션 라벨. 개수 표기·보조 안내 문구는 두지 않는다(PRES-B-02).
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
            // Select all 은 섹션 라벨 옆이 아니라 **행 오른쪽 끝**이다 — 아래 체크박스 열과 맞춘다.
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

/// OPTIONAL 섹션 전체 토글. 중간 상태를 그리지 않는다 — 전부 켜졌을 때만 체크로 보인다.
private struct VpSelectAll: View {
    let allOn: Bool
    let onToggle: () -> Void

    var body: some View {
        // 라벨과 체크박스가 한 버튼이다 — 텍스트만 눌러도 토글된다(탭 영역이 22dp 를 넘도록).
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
                // 라벨은 원형 그대로 — SD-JWT 는 이 값이 곧 클레임 키라 대문자 변환이 데이터 변형이 된다.
                // (W3C 는 스키마 caption 이지만 상세화면이 이미 원형으로 그려 표기를 맞춘다.)
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
    }
}

/// 제시화면 클레임 값 — 텍스트 또는 이미지. 이미지는 값 텍스트를 대신하며(PRES-B-04),
/// 체크박스는 우측에 그대로 남는다. 표시 가능 폭이 상세화면보다 좁을 뿐 크기 규칙은 같다.
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

/// 하위를 가진 항목 — 상위 체크박스 하나로 서브트리 전체를 토글하고 하위는 **표시 전용**이다
/// (PRES-B-03). 체크박스 탭과 펼침 토글은 서로 분리돼 동작한다.
private struct VpClaimGroup: View {
    let title: String
    let children: [VpChildRow]
    /// nil 이면 체크할 수 없는 그룹이다 — REQUIRED 그룹이거나 미선택 옵션 카드다.
    /// 펼치고 접는 것만 동작한다.
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

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                        VpClaimRow(
                            // 하위 라벨 = object 키 원형. 배열 원소는 라벨이 비어 값만 그린다.
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
