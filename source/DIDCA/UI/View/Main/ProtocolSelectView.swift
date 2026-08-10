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

/// 발급 프로토콜 선택 화면 (화면설계서 18a). "From list" 진입 시 addCertificate 앞단에 표시된다.
/// - Open DID: 현행 TAS 플랜 리스트(AddCertificateView)로 진입.
/// - OID4VCI: 현재 미제공 — 안내 토스트. 후속(목록사업자 URL 변경) 작업 예정.
struct ProtocolSelectView: View {

    var onBack: () -> Void = {}
    var onSelectOpenDID: () -> Void = {}
    var onSelectOID4VCI: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "Select Issuance Protocol", style: .uppercase)
                    .padding(.top, 20)
                    .padding(.horizontal, 20)

                VStack(spacing: 10) {
                    optionCard(
                        title: "Open DID",
                        desc: "OmniOne for Verifiable Credential Issuance.",
                        action: onSelectOpenDID
                    )
                    optionCard(
                        title: "OID4VCI",
                        desc: "OpenID for Verifiable Credential Issuance.",
                        action: onSelectOID4VCI
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.backgroundGray)
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

    private func optionCard(title: String, desc: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.pretendard(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                    Text(desc)
                        .font(.pretendard(size: 12, weight: .regular))
                        .foregroundStyle(.customGray)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(.icChevD)
                    .renderingMode(.template)
                    .foregroundStyle(.customPrimary)
                    .rotationEffect(.degrees(-90))
            }
            .padding(16)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.borderGray, lineWidth: 1)
            )
            .shadow(color: .primaryShadow.opacity(0.06), radius: 1.5, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ProtocolSelectView()
}
