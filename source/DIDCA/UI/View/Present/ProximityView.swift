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

/// Proximity presentation (Present · Proximity, iOS).
///
/// iOS doesn't support holder-side NFC Device Engagement, so the bottom "Or share via NFC" area is
/// **not rendered at all**. No disabled state or unsupported notice either; proximity presentation
/// is a single QR Device Engagement path. For the same reason Settings has no Proximity group.
///
/// The QR text is the communication SDK's engagement — the coordinator opens the session (`startProximity`) and this screen
/// only draws its result (`qrString`). When a reader attaches and sends a request, the coordinator stacks the consent screen on top.
struct ProximityView: View {
    /// Engagement QR text. nil until the session opens — only an empty card is shown meanwhile.
    var qrString: String?
    var onBack: () -> Void = {}
    var onStart: () async -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            // The primary-background title bar serves as the screen title, so no large title in the body.
            HStack {
                Button(action: onBack) {
                    Image(.icBack)
                        .renderingMode(.template)
                        .foregroundStyle(.white)
                        .padding()
                }
                .accessibilityIdentifier("backButton")
                Text("Present in Person")
                    .font(.pretendard(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                Image(.icBack).padding().hidden()
            }
            .frame(height: 56)
            .background(Color.customPrimary.ignoresSafeArea(edges: .top))

            Text("Show this QR code to the Relying Party to present your digital certificate.")
                .font(.pretendard(size: 13, weight: .regular))
                .foregroundStyle(.customGray)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 16)

            // With no bottom NFC area, the QR is centered within the remaining space.
            Spacer()
            Group {
                if let qrString {
                    QRCodeView(content: qrString, size: 240)
                        .accessibilityIdentifier("qrImage")
                } else {
                    Color.clear.frame(width: 240, height: 240)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white)
                    .stroke(.borderGray, lineWidth: 1)
            )
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.backgroundGray)
        .task { await onStart() }
    }
}

#Preview {
    ProximityView(qrString: "mdoc:owBjMS4wAYIB2BhYS6QBAiABIVggWojRgrzl")
}
