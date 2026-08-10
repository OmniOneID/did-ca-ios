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
import UIKit

struct SettingsMenuView: View {

    @Environment(AppCoordinator.self) private var coordinator

    var did: String = "did:omn:3HGkH69exrvG5HWKZ6YAfUteHLC"
    var onBack: () -> Void = {}
    var onChangePin: () -> Void = {}
    var onChangeUnlockPin: () -> Void = {}
    var onAddBiometrics: () -> Void = {}
    var onResetApp: () -> Void = {}

    @State private var showCopiedToast: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image(.icBack)
                        .renderingMode(.template)
                        .foregroundStyle(.white)
                        .padding()
                }
                Text("Settings")
                    .font(.pretendard(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                Image(.icBack).padding().hidden()
            }
            .frame(height: 56)
            .background(Color.customPrimary.ignoresSafeArea(edges: .top))

            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "Information")
                    HStack(alignment: .center, spacing: 8) {
                        Text(did)
                            .font(.pretendard(size: 14, weight: .regular))
                            .foregroundStyle(.black)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button(action: copyDid) {
                            Image(.icCopy)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.white)
                            .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
                    )
                }

                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "General")
                    VStack(spacing: 0) {
                        SettingsRow(title: "Change PIN", action: onChangePin)
                        Rectangle().fill(.borderGray).frame(height: 1)
                        SettingsRow(title: "Change Unlock PIN", action: onChangeUnlockPin)
                        Rectangle().fill(.borderGray).frame(height: 1)
                        SettingsRow(title: "Add Biometrics", action: onAddBiometrics)
                        Rectangle().fill(.borderGray).frame(height: 1)
                        SettingsRow(title: "Reset App") {
                            OverlayManager.shared.showPopup(
                                title: "Reset App",
                                message: "Resetting will permanently erase all stored data (VCs, PIN, etc.) and cannot be undone. Continue?",
                                primaryButtonTitle: "Reset",
                                primaryAction: { onResetApp() },
                                secondaryButtonTitle: "Cancel"
                            )
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(.borderGray, lineWidth: 1)
                            .fill(.white)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(16)

            Spacer()
        }
        .background(.backgroundGray)
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                Text("DID copied to clipboard")
                    .font(.pretendard(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(Color.black.opacity(0.92))
                    )
                    .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
                    .padding(.bottom, 32)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private func copyDid() {
        UIPasteboard.general.string = did
        withAnimation(.easeOut(duration: 0.2)) {
            showCopiedToast = true
        }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeOut(duration: 0.2)) {
                showCopiedToast = false
            }
        }
    }
}

private struct SettingsRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(title)
                    .font(.pretendard(size: 15, weight: .medium))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(.icChevR)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsMenuView()
        .environment(AppCoordinator())
}
