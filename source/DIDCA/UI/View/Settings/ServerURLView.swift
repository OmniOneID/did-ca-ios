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

/// Settings · Server URL (design spec 29a~29d · SRV-01~09).
///
/// From the top, two cards — the Custom section and the Default section — run in a single scroll (SRV-02). Each of the
/// 6 endpoints is in exactly one of the two sections, and moves only via the item's right button (Custom / Default) and the
/// section header's bulk button (All Custom / All Default). Saving is committed only by Save and applies to networking immediately
/// (SRV-07 · SRV-E-07) — there is no completion dialog or restart notice.
struct ServerURLView: View {

    /// false when entered from the server settings popup on first-launch Splash (SPL-03) — the app hasn't been entered yet,
    /// so there is no AppBar back and the bottom Cancel is the only exit (SRV-01 · 29d).
    var showsBack: Bool = true
    /// Cancel · Back · system back · Save all close through this one — returning on the stack is the caller's job.
    /// `saved` tells whether it closed via Save — used where the return path depends on whether it was saved (ONB-E-04).
    var onClose: (_ saved: Bool) -> Void = { _ in }

    @State private var viewModel = ServerURLViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { onClose(false) }) {
                    Image(.icBack)
                        .renderingMode(.template)
                        .foregroundStyle(.white)
                        .padding()
                }
                .opacity(showsBack ? 1 : 0)
                .disabled(!showsBack)
                Text("Server URL")
                    .font(.pretendard(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                Image(.icBack).padding().hidden()
            }
            .frame(height: 56)
            .background(Color.customPrimary.ignoresSafeArea(edges: .top))

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    customSection
                    defaultSection
                }
                .padding(16)
            }

            bottomBar
        }
        .background(.backgroundGray)
    }

    // MARK: - Custom

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHead("Custom") {
                // Bulk Default (move down) is gray — if both were primary you couldn't tell which is the current state.
                ServerURLRowButton(title: "All Default", muted: true,
                                   disabled: viewModel.customList.isEmpty,
                                   action: viewModel.allToDefault)
            }
            card {
                if viewModel.customList.isEmpty {
                    emptyNote("No custom endpoints.\nTap Custom on an endpoint below to edit it.")
                }
                ForEach(Array(viewModel.customList.enumerated()), id: \.element) { index, endpoint in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            rowLabel(endpoint)
                            Spacer()
                            ServerURLRowButton(title: "Default", muted: true) {
                                viewModel.toDefault(endpoint)
                            }
                        }
                        ServerURLField(text: viewModel.binding(for: endpoint),
                                       placeholder: endpoint.defaultValue,
                                       error: viewModel.errors[endpoint])
                    }
                    .padding(.vertical, 12)
                    if index < viewModel.customList.count - 1 { Divider() }
                }
            }
        }
    }

    // MARK: - Default

    private var defaultSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHead("Default") {
                ServerURLRowButton(title: "All Custom",
                                   disabled: viewModel.defaultList.isEmpty,
                                   action: viewModel.allToCustom)
            }
            card {
                if viewModel.defaultList.isEmpty {
                    emptyNote("All endpoints are set to custom.")
                }
                ForEach(Array(viewModel.defaultList.enumerated()), id: \.element) { index, endpoint in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            rowLabel(endpoint)
                            // Shown in full without truncation — URLs have no spaces, so they wrap **per character** (SRV-03).
                            // SwiftUI can't set the line-break mode directly, so zero-width spaces are inserted between characters
                            // so it can break after any character (display-only text, not a copy target).
                            Text(Self.charWrappable(endpoint.defaultValue))
                                .font(.pretendard(size: 13, weight: .regular))
                                .foregroundStyle(.customGray)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        ServerURLRowButton(title: "Custom") {
                            viewModel.toCustom(endpoint)
                        }
                    }
                    .padding(.vertical, 12)
                    if index < viewModel.defaultList.count - 1 { Divider() }
                }
            }
        }
    }

    // MARK: - Pieces

    /// Section header — the same marker as SectionHeader, with a bulk-move button on the right (SRV-02).
    private func sectionHead<Action: View>(_ title: String,
                                           @ViewBuilder action: () -> Action) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(.accentOrange)
                .frame(width: 4, height: 16)
            Text(title)
                .font(.pretendard(size: 13, weight: .bold))
                .kerning(-0.1)
                .foregroundStyle(.black)
            Spacer()
            action()
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white)
                    .stroke(.borderGray, lineWidth: 1)
            )
    }

    /// An empty section keeps its card and shows a notice instead (SRV-02). Left-aligned; line breaks are set by the text.
    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(.pretendard(size: 13, weight: .regular))
            .foregroundStyle(.customGray)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
    }

    /// For per-character wrapping — inserts U+200B after each character (break-all).
    private static func charWrappable(_ text: String) -> String {
        text.map(String.init).joined(separator: "\u{200B}")
    }

    private func rowLabel(_ endpoint: ServerEndpoint) -> some View {
        Text(endpoint.label)
            .font(.pretendard(size: 13, weight: .semibold))
            .foregroundStyle(.black)
    }

    // MARK: - Bottom fixed actions

    private var bottomBar: some View {
        HStack(spacing: 10) {
            // Cancel is always enabled — closes without confirmation regardless of changes (SRV-08 · SRV-E-06).
            Button(action: { onClose(false) }) {
                Text("Cancel")
                    .font(.pretendard(size: 16, weight: .semibold))
                    .foregroundStyle(.customPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.customPrimary, lineWidth: 1.5)
                    )
            }

            Button(action: save) {
                Text("Save")
                    .font(.pretendard(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(viewModel.canSave
                                  ? Color.customPrimary
                                  : Color(red: 248/255, green: 215/255, blue: 184/255))
                    )
                    .shadow(color: viewModel.canSave ? .customPrimary.opacity(0.3) : .clear,
                            radius: 3, x: 0, y: 2)
            }
            .disabled(!viewModel.canSave)
        }
        .padding(16)
        .background(
            Rectangle()
                .fill(.white)
                .overlay(Rectangle().frame(height: 1).foregroundStyle(.borderGray), alignment: .top)
        )
    }

    // MARK: - Actions

    /// SRV-07 — closes immediately after saving. No completion dialog. Saved values are used from the next request on (SRV-E-07).
    private func save() {
        guard viewModel.save() else {
            // SRV-E-05 — leave the input values and section layout on screen as is and don't touch the existing settings.
            OverlayManager.shared.showPopup(
                title: "Failed to save",
                message: "Failed to save. Try again.",
                primaryButtonTitle: "OK"
            )
            return
        }
        onClose(true)
    }
}

/// Small move button on the item's right. Custom (move up) is primary, Default (move down) is gray (`muted`).
private struct ServerURLRowButton: View {
    let title: String
    var muted: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.pretendard(size: 13, weight: .semibold))
                .foregroundStyle(disabled ? .gray500 : muted ? .customGray : .customPrimary)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(disabled || muted ? Color.borderGray : .customPrimary, lineWidth: 1)
                )
        }
        .disabled(disabled)
    }
}

/// Single-line URL input — on a format error, the border turns the error color and an inline message is attached below
/// (SRV-E-01 · E-02 · E-03).
private struct ServerURLField: View {
    @Binding var text: String
    let placeholder: String
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(placeholder, text: $text)
                .font(.pretendard(size: 14, weight: .regular))
                .foregroundStyle(.black)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white)
                        .stroke(error == nil ? Color.borderGray : .customRed, lineWidth: 1.5)
                )

            if let error {
                Text(error)
                    .font(.pretendard(size: 12, weight: .regular))
                    .foregroundStyle(.customRed)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    ServerURLView()
}

#Preview("from Splash") {
    ServerURLView(showsBack: false)
}
