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

/// Web form for additional issuance info (`DEMO_URL/addVcInfo`).
/// Composes the generic `WebView`, and maps only the JS callbacks the addVcInfo page promises into results here.
/// - `onCompletedAddVcUpload` → upload succeeded → `onResult(true)`
/// - `onFailedAddVcUpload`    → upload failed → `onResult(false)`
/// - Closed with the X button → `onResult(false)`
struct IssueWebFormView: View {

    let url: URL
    /// Whether the form completed. true continues issuance, false aborts it.
    let onResult: (Bool) -> Void

    @State private var isLoading = true

    private static let completedHandler = "onCompletedAddVcUpload"
    private static let failedHandler = "onFailedAddVcUpload"

    var body: some View {
        VStack(spacing: 0) {
            // It's a modal, so the left is X — closing cancels the form (aborts issuance).
            NavBar(title: "Add certificate information", icon: .icCloseWhite) {
                onResult(false)
            }

            ZStack {
                WebView(
                    url: url,
                    messageHandlers: [Self.completedHandler, Self.failedHandler],
                    onMessage: { name, _ in
                        onResult(name == Self.completedHandler)
                    },
                    onLoadingChanged: { isLoading = $0 },
                    // The JS bridge above is authoritative for the issuance result. Incidental alert/confirm/prompt from the page
                    // are not shown as popups but acked immediately — same behavior as did-ca.
                    silenceJSDialogs: true
                )

                if isLoading {
                    ProgressView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.backgroundGray)
    }
}
