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
import DIDWalletSDK

/// OID4VCI 발급 — 프로토콜 선택에서 바로 진입한다. Issuer 선택 단계를 따로 두지 않고,
/// 목록사업자가 내려준 Issuer 를 **섹션 헤더(`credentialIssuer`)로 구분해 한 화면에** 펼친다.
///
/// 크리덴셜 이름은 configuration id 를 그대로 쓴다(현재 서버 metadata 에 `display.name` 없음).
/// SD-JWT 와 mDoc 은 둘 다 선택·발급 가능하다(`isIssuable`). 앱이 표시할 줄 모르는 포맷만
/// 선택 불가로 둔다 — 끝까지 진행시키면 클레임을 다 입력한 뒤 마지막 단계에서 실패한다.
struct CredentialSelectView: View {

    @Environment(AppCoordinator.self) private var coordinator
    @State private var vm = CredentialSelectViewModel()

    var onBack: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(vm.sections) { section in
                        issuerSection(section)
                    }

                    // 조회 실패는 팝업으로 알리고 Docs 로 돌아가므로, 이 문구는 "0건" 전용이다.
                    if !vm.isLoading && vm.sections.isEmpty {
                        Text("No issuers support this protocol yet.")
                            .font(.pretendard(size: 13, weight: .regular))
                            .foregroundStyle(.customGray)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.backgroundGray)
        .task { await vm.load(coordinator: coordinator) }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Image(.icBackWhite).padding()
            }

            Text("Add certificate")
                .font(.pretendard(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            Image(.icBackWhite).padding().hidden()
        }
        .frame(height: 56)
        .background { Color.customPrimary.ignoresSafeArea(edges: .top) }
    }

    private func issuerSection(_ section: CredentialSelectViewModel.IssuerSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Issuer 식별자는 서버가 준 값(스펙상 URL)이라 대문자 변환 없이 원형으로 보인다.
            // 발급 목록 계열의 헤더 모양(11pt·커닝 0.3·primary 막대)은 그대로 유지.
            SectionHeader(title: section.issuer.credentialIssuer,
                          style: .uppercase,
                          preservesCase: true)
                .padding(.horizontal, 20)

            VStack(spacing: 10) {
                ForEach(section.configurations) { config in
                    Button {
                        Task {
                            await coordinator.startOID4VciWebIssuance(
                                issuer: section.issuer,
                                metadata: section.metadata,
                                configurationId: config.id
                            )
                        }
                    } label: {
                        configurationRow(config)
                    }
                    .buttonStyle(.plain)
                    .disabled(!config.isIssuable)
                }

                if section.configurations.isEmpty {
                    Text("No credentials available to issue.")
                        .font(.pretendard(size: 13, weight: .regular))
                        .foregroundStyle(.customGray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }

    private func configurationRow(_ config: CredentialSelectViewModel.Configuration) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(config.id)
                    .font(.pretendard(size: 14, weight: .semibold))
                    .foregroundStyle(config.isIssuable ? .black : .customGray)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    if let badge = config.badge {
                        FormatBadge(kind: badge)
                    }
                    if !config.isIssuable {
                        Text("Not supported yet")
                            .font(.pretendard(size: 11, weight: .regular))
                            .foregroundStyle(.customGray)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if config.isIssuable {
                Image(.icAddOrange)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.paleOrange))
            }
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.borderGray, lineWidth: 1)
        )
        .shadow(color: .primaryShadow.opacity(0.06), radius: 1.5, x: 0, y: 1)
        .opacity(config.isIssuable ? 1 : 0.6)
    }
}

#Preview {
    CredentialSelectView()
        .environment(AppCoordinator())
}
