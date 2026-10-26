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

/// OID4VCI issuance — entered directly from protocol selection. There is no separate Issuer selection step;
/// the Issuers returned by the directory provider are laid out **on one screen, separated by section headers (`credentialIssuer`)**.
///
/// Credential names use the configuration id as-is (current server metadata has no `display.name`).
/// Both SD-JWT and mDoc are selectable and issuable (`isIssuable`). Only formats the app can't display
/// are made unselectable — carrying them through would fail at the last step after all claims were entered.
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

                    // A fetch failure is reported via popup and returns to Docs, so this text is for the "0 results" case only.
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
            // The Issuer identifier is the server-provided value (a URL per spec), so it's shown as-is without uppercasing.
            // The issuance-list header style (11pt · kerning 0.3 · primary bar) is kept.
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
