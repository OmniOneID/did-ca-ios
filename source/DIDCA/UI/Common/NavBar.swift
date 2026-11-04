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

/// App-wide top bar — an orange (`customPrimary`) background covers up to the status bar, with a white title in the center.
/// The orange band's total height is `56 + status bar`.
///
/// The content height is just 56 and `safeAreaPadding(.top)` is not applied — this bar is already placed inside the safe
/// area within NavigationStack / fullScreenCover, so adding it again would count the status bar height twice
/// and make the band thicker by the status bar. Only the background needs `ignoresSafeArea` to cover the top.
///
/// The left icon defaults to back (←), and the right is an equally sized blank to keep the title dead center.
/// A component made so the issuance web views use the same top as the screen before them; other screens still
/// each have the same shape inline (unification is a follow-up).
struct NavBar: View {

    let title: String
    var icon: ImageResource = .icBackWhite
    let action: () -> Void

    var body: some View {
        HStack {
            Button(action: action) {
                Image(icon).padding()
            }
            .accessibilityIdentifier(icon == .icCloseWhite ? "closeButton" : "backButton")

            Text(title)
                .font(.pretendard(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            Image(icon).padding().hidden()
        }
        .frame(height: 56)
        .background { Color.customPrimary.ignoresSafeArea(edges: .top) }
    }
}

#Preview {
    VStack(spacing: 0) {
        NavBar(title: "Add certificate information") {}
        Spacer()
    }
}
