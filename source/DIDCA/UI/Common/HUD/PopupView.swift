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
            Color.black.opacity(0.45)
                .ignoresSafeArea()
//                .onTapGesture {
//                    onDismiss()
//                }

            VStack(spacing: 14) {
                Text(LocalizedStringResource(stringLiteral:popup.title))
                    .font(.pretendard(size: 18, weight: .bold))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
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
                }
////                .padding(.horizontal, 8)
//                .padding(.bottom, 8)
                
            }
            .padding(24)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
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
            secondaryButton: nil)) {
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
            )
        )
    )
    {
        ()
    }
}
