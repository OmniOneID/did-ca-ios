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

struct IssueSuccessView: View {
    var items: [String] = ["National ID Card"]
    var onClose: () -> Void = {}

    @State private var haloShown = false
    @State private var popShown = false
    @State private var checkShown = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 56)

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(.paleOrange)
                        .frame(width: 96, height: 96)
                        .scaleEffect(haloShown ? 1.0 : 0.3)
                        .opacity(haloShown ? 1 : 0)

                    Circle()
                        .fill(.customPrimary)
                        .frame(width: 64, height: 64)
                        .overlay {
                            Image(.icCheckLarge)
                                .renderingMode(.template)
                                .foregroundStyle(.white)
                                .scaleEffect(checkShown ? 1.0 : 0)
                                .opacity(checkShown ? 1 : 0)
                        }
                        .scaleEffect(popShown ? 1.0 : 0)
                }
                .padding(.top, 24)
                .onAppear { runSuccessAnimation() }

                Text("Successfully added to your wallet")
                    .font(.pretendard(size: 18, weight: .semibold))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    ForEach(items, id: \.self) { name in
                        HStack(spacing: 10) {
                            Image(.icId)
                                .frame(width: 28, height: 28)
                            Text(name)
                                .font(.pretendard(size: 14, weight: .semibold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.paleOrange)
                                .stroke(.borderOrange, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, 16)

            Spacer()

            VStack {
                Button(action: onClose) {
                    Text("Close")
                        .font(.pretendard(size: 16, weight: .semibold))
                        .foregroundStyle(.customPrimary)
                        .frame(height: 52)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.customPrimary, lineWidth: 1.5)
                        )
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .background(
                Rectangle()
                    .fill(.backgroundGray)
                    .overlay(Rectangle().frame(height: 1).foregroundStyle(.borderGray), alignment: .top)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.backgroundGray)
    }

    private func runSuccessAnimation() {
        haloShown = false
        popShown = false
        checkShown = false

        withAnimation(.timingCurve(0.34, 1.56, 0.64, 1.0, duration: 0.46)) {
            haloShown = true
        }
        withAnimation(.timingCurve(0.34, 1.56, 0.64, 1.0, duration: 0.56).delay(0.16)) {
            popShown = true
        }
        withAnimation(.easeOut(duration: 0.34).delay(0.46)) {
            checkShown = true
        }
    }
}

#Preview("Single") {
    IssueSuccessView()
}

#Preview("Multiple") {
    IssueSuccessView(items: [
        "Mobile Driving Licence",
        "National ID Card",
        "Resident Registration Card"
    ])
}
