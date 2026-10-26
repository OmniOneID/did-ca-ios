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

struct AddCertificateView: View {

    @Environment(AppCoordinator.self) private var coordinator
    @State private var vm = AddCertificateViewModel()

    var onBack: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Capsule()
                        .frame(width: 4, height: 16)
                        .foregroundStyle(.customPrimary)

                    Text("Digital Credentials Issuer")
                        .font(.pretendard(size: 11, weight: .bold))
                        .kerning(0.3)
                        .textCase(.uppercase)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 20)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(vm.plans, id: \.vcPlanId) { plan in
                            Button {
                                Task { await vm.pick(plan, coordinator: coordinator) }
                            } label: {
                                planRow(plan)
                            }
                            .buttonStyle(.plain)
                        }

                        // While loading, the HUD covers the screen, so there's no inline indicator.
                        // The isLoading guard keeps the "empty" message from flickering during loading.
                        if !vm.isLoading && vm.plans.isEmpty {
                            Text("No credentials available to issue.")
                                .font(.pretendard(size: 13, weight: .regular))
                                .foregroundStyle(.customGray)
                                .padding(.top, 24)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
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

    // Screen design spec (ScrDocsAddList, 19): a plan row is title(name) + a VC format badge below it + a + button on the right.
    // The format badge depends on the selected protocol — this screen is the Open DID issuance path, so it's VC only.
    // (The OID4VCI path is SD-JWT·mDoc and is follow-up work.)
    private func planRow(_ plan: VCPlan) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(plan.name)
                    .font(.pretendard(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                FormatBadge(kind: .vc)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(.icAddOrange)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.paleOrange))
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
}

#Preview {
    AddCertificateView()
        .environment(AppCoordinator())
}
