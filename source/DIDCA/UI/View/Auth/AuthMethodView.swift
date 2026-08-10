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

struct AuthMethodView: View {
    var onBack: () -> Void = {}
    var onPin: () -> Void = {}
    var onBiometrics: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image(.icBack)
                        .renderingMode(.template)
                        .foregroundStyle(.white)
                        .padding()
                }
                Text("Authentication")
                    .font(.pretendard(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                Image(.icBack)
                    .padding()
                    .hidden()
            }
            .frame(height: 56)
            .background(Color.customPrimary.ignoresSafeArea(edges: .top))

            VStack(spacing: 12) {
                AuthMethodOption(
                    icon: .icKeypad,
                    title: "PIN",
                    description: "Sign in with your 6-digit PIN.",
                    action: onPin
                )
                AuthMethodOption(
                    icon: .icFingerSmall,
                    title: "Biometrics",
                    description: "Use fingerprint or face recognition.",
                    action: onBiometrics
                )
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundGray.ignoresSafeArea())
    }
}

private struct AuthMethodOption: View {
    let icon: ImageResource
    let title: String
    let description: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(icon)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.paleOrange)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.pretendard(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                    Text(description)
                        .font(.pretendard(size: 13, weight: .regular))
                        .foregroundStyle(.customGray)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(.icChevR)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.borderGray, lineWidth: 1.5)
            )
            .shadow(color: .primaryShadow.opacity(0.06), radius: 1.5, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AuthMethodView()
}
