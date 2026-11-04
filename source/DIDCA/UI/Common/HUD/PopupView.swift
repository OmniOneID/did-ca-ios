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

struct Popup: Identifiable, Equatable {
    let id: UUID = UUID()
    let title: String
    let message: String
    let primaryButton: PopupButton
    let secondaryButton: PopupButton?
    /// Text link placed **below** the button row.
    /// Meant only as an escape route that closes the dialog and sends to another screen, so not used for destructive actions.
    let linkButton: PopupButton?
    
    struct PopupButton: Equatable {
        let title: String
        let action: () -> Void
        
        static func == (lhs: PopupButton, rhs: PopupButton) -> Bool {
            lhs.title == rhs.title
        }
    }
    
    static func == (lhs: Popup, rhs: Popup) -> Bool {
        lhs.id == rhs.id
    }
}

struct PopupView: View {
    let popup: Popup
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            // A backdrop tap closes the dialog the same way its default button does:
            // OK for a single-button dialog, Cancel (the secondary button) for a dual-button one. Every call site's
            // actions already move on to the next screen, so closing never strands the user on a finished screen.
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    (popup.secondaryButton ?? popup.primaryButton).action()
                    onDismiss()
                }

            VStack(spacing: 14) {
                Text(LocalizedStringResource(stringLiteral:popup.title))
                    .font(.pretendard(size: 18, weight: .bold))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("dialogTitle")
                
                Text(LocalizedStringResource(stringLiteral:popup.message))
                    .font(.pretendard(size: 14, weight: .regular))
                    .foregroundStyle(.customGray)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(spacing: 10) {
                    if let secondary = popup.secondaryButton {
                        Button(role: .cancel) {
                            secondary.action()
                            onDismiss()
                        } label: {
                            Text(LocalizedStringResource(stringLiteral:secondary.title))
                                .font(
                                    .pretendard(
                                        size: 16,
                                        weight: .semibold
                                    )
                                )
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .foregroundStyle(.customPrimary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            .customPrimary,
                                            lineWidth: 1.5
                                        )
                                )
                        }
                        .accessibilityIdentifier("dialogCancelButton")
                    }
                    
                    Button {
                        popup.primaryButton.action()
                        onDismiss()
                    } label: {
                        Text(LocalizedStringResource(stringLiteral:popup.primaryButton.title))
                            .font(
                                .pretendard(
                                    size: 16,
                                    weight: .semibold
                                )
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .foregroundStyle(.white)
                            .background(Color.customPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .customPrimary.opacity(0.3), radius: 3, x: 0, y: 2)
                    }
                    // A lone OK is `dialogButton`; with a secondary beside it the primary is the confirm action.
                    .accessibilityIdentifier(popup.secondaryButton == nil ? "dialogButton" : "dialogConfirmButton")
                }
////                .padding(.horizontal, 8)
//                .padding(.bottom, 8)

                // OK is the default action and the link is reachable only via this path (never auto-selected).
                if let link = popup.linkButton {
                    Button {
                        link.action()
                        onDismiss()
                    } label: {
                        Text(LocalizedStringResource(stringLiteral: link.title))
                            .font(.pretendard(size: 14, weight: .semibold))
                            .foregroundStyle(.customPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                    .accessibilityIdentifier("dialogLink")
                }
            }
            .padding(24)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            // Taps on the card's empty area must not fall through to the backdrop.
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .onTapGesture {}
            .padding(24)
            .transition(.scale(scale: 0.7).combined(with: .opacity))
        }
    }
}

#Preview {
    
    
    
    
    PopupView(
        popup: .init(
            title: "Warning",
            message: "Not sharing certain data may cause the requested credential issuance to fail.",
            primaryButton: .init(
                title: "Got it", action: {
                    ()
                }
            ),
            secondaryButton: nil,
            linkButton: nil)) {
        ()
    }
    
    
    PopupView(
        popup: .init(
            title: "Delete certificate?",
            message: "This certificate will be permanently\ndeleted from your wallet and may affect\nyour access to services.",
            primaryButton: .init(
                title: "Delete", action: {
                    ()
                }
            ),
            secondaryButton: .init(
                title: "Cancel", action: {
                    ()
                }
            ),
            linkButton: nil
        )
    )
    {
        ()
    }
}
