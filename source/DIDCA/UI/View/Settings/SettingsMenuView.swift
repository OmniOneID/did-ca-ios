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
    var onServerUrl: () -> Void = {}

    /// username provided by the registration web view. If empty, the name row is hidden.
    var userName: String? = Preference.getUserName()

    /// Copy toast message — hidden when nil. Each row has a different message (DID · User name).
    @State private var copiedToast: String? = nil
    /// BLE Transfer Mode selection sheet. Preference holds the source of truth; the screen keeps a copy only for display.
    @State private var showBleModeSheet: Bool = false
    @State private var bleMode: BleTransferMode = Preference.bleTransferMode
    /// The sheet model keeps a single instance and only swaps `contents` — recreating the sheet (id change) cuts off
    /// the dismiss animation and it vanishes in place.
    @State private var bleModeSheetModel = ActionSheetViewModel(
        title: "BLE Transfer Mode",
        message: "Which BLE role this wallet takes when sending data to a reader.",
        contents: []
    )

    var body: some View {
        ZStack(alignment: .bottom) {
            content
            bleModeSheet
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image(.icBack)
                        .renderingMode(.template)
                        .foregroundStyle(.white)
                        .padding()
                }
                .accessibilityIdentifier("backButton")
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
                    // Each row is label + value + copy button. First row User Name, second row DID.
                    // If the name is empty, only the DID row remains, with no empty row or placeholder.
                    VStack(spacing: 0) {
                        if let userName, !userName.isEmpty {
                            infoRow(label: "User Name", value: userName,
                                    toast: "User name copied to clipboard",
                                    valueID: "userNameText", copyID: "copyUserNameButton")
                            Rectangle().fill(.borderGray).frame(height: 1)
                        }
                        infoRow(label: "DID", value: did, toast: "DID copied to clipboard",
                                breaksAnywhere: true,
                                valueID: "didText", copyID: "copyDidButton")
                    }
                    .padding(.horizontal, 16)
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
                        // Top of General.
                        SettingsRow(title: "Server URL", action: onServerUrl)
                        Rectangle().fill(.borderGray).frame(height: 1)
                        SettingsRow(title: "Change PIN", action: onChangePin)
                        Rectangle().fill(.borderGray).frame(height: 1)
                        SettingsRow(title: "Change Unlock PIN", action: onChangeUnlockPin)
                        Rectangle().fill(.borderGray).frame(height: 1)
                        SettingsRow(title: "Add Biometrics", action: onAddBiometrics)
                        Rectangle().fill(.borderGray).frame(height: 1)
                        SettingsRow(title: "Reset App") {
                            OverlayManager.shared.showPopup(
                                title: "Reset App",
                                message: "Resetting will permanently erase all stored data (VCs, PIN, server settings, etc.) and cannot be undone. Continue?",
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

                // BLE has no platform constraints, so it's shown on both Android · iOS.
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "Proximity")
                    // Both the label and current value are long and would be cut off on small devices in a single right-aligned line — 2-line stack.
                    // This one row is the whole setting, with no screen navigation.
                    Button(action: { showBleModeSheet = true }) {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("BLE Transfer Mode")
                                    .font(.pretendard(size: 15, weight: .medium))
                                    .foregroundStyle(.black)
                                Text(bleMode.label)
                                    .font(.pretendard(size: 13, weight: .regular))
                                    .foregroundStyle(.customGray)
                                    .accessibilityIdentifier("bleTransferModeValue")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Image(.icChevR)
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("bleTransferModeRow")
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
            if let copiedToast {
                Text(copiedToast)
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

    /// Lists the three options in Both → Central → Peripheral order; tapping saves and closes immediately.
    /// Closing by dim tap · drag leaves the value unchanged. When the current value changes, only the row's checkmark position updates.
    private var bleModeSheet: some View {
        DraggableActionSheet(isPresented: $showBleModeSheet, viewModel: bleModeSheetModel)
            .onAppear { bleModeSheetModel.contents = bleModeRows() }
            .onChange(of: bleMode) { _, _ in bleModeSheetModel.contents = bleModeRows() }
    }

    private func bleModeRows() -> [ActionSheetContent] {
        BleTransferMode.allCases.map { mode in
            .init(title: mode.label,
                  selected: mode == bleMode,
                  action: {
                      Preference.bleTransferMode = mode
                      bleMode = mode
                  })
        }
    }

    /// - Parameter breaksAnywhere: per-character wrapping (used for the DID) — inserts zero-width spaces into the display string only
    ///   so a value without spaces doesn't break only after `:`. The copied value is the original as is.
    private func infoRow(label: String, value: String, toast: String,
                         breaksAnywhere: Bool = false,
                         valueID: String, copyID: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.pretendard(size: 12, weight: .regular))
                    .foregroundStyle(.customGray)
                Text(breaksAnywhere ? value.map(String.init).joined(separator: "\u{200B}") : value)
                    .font(.pretendard(size: 14, weight: .regular))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    // Expose the original value, not the zero-width-space display copy.
                    .accessibilityLabel(value)
                    .accessibilityIdentifier(valueID)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { copy(value, toast: toast) } label: {
                Image(.icCopy)
            }
            .accessibilityIdentifier(copyID)
        }
        .padding(.vertical, 12)
    }

    private func copy(_ text: String, toast: String) {
        UIPasteboard.general.string = text
        withAnimation(.easeOut(duration: 0.2)) {
            copiedToast = toast
        }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeOut(duration: 0.2)) {
                // If another row was copied in the meantime, that toast is dismissed by its own timer.
                if copiedToast == toast { copiedToast = nil }
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
