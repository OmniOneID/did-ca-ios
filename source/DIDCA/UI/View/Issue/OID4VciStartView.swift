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

/// OID4VCI user claim input WebView (integration guide §6·§11).
///
/// Only shows the input screen provided by the Issuer — no JS bridge is registered, and input values / DID are
/// not brought into the app. Completion arrives solely via an `openid-credential-offer://` navigation,
/// and its handling (parsing · validation · duplicate prevention · closing the modal) is up to the coordinator.
///
/// Security settings: JS disabled (the server screen doesn't use JS), navigation outside the Issuer host blocked, custom schemes
/// other than the completion scheme and external app launches blocked, no SSL error bypass (unhandled challenge = default reject).
struct OID4VciStartView: View {

    let url: URL
    /// Allowed host — the start URL's host. Only the same Issuer's screens and form submits go back and forth.
    let allowedHost: String
    /// Closed with the X button → issuance cancelled.
    let onClose: () -> Void
    /// Intercepts the `openid-credential-offer://` navigation → the coordinator handles completion.
    let onCompletionURI: (URL) -> Void

    @State private var isLoading = true
    // Load-failure state — when set, an error screen covers the web content. The associated value is the HTTP status code
    // (nil if the transfer itself failed).
    @State private var failure: LoadFailure? = nil
    // Retry counter. When it changes, a new WebView is created and reopens the start URL.
    // It doesn't increment on rotation or view re-creation, so no server issuance session is created arbitrarily —
    // a new session only happens when the user explicitly retries.
    @State private var attempt = 0

    var body: some View {
        VStack(spacing: 0) {
            // It's a modal, so the left is X — closing cancels issuance.
            NavBar(title: "Add certificate information", icon: .icCloseWhite, action: onClose)

            ZStack {
                WebView(
                    url: url,
                    onLoadingChanged: { isLoading = $0 },
                    allowedHosts: [allowedHost],
                    completionScheme: OID4VciIssuerDirectory.completionScheme,
                    onCompletionURI: onCompletionURI,
                    onLoadFailure: { status in failure = LoadFailure(statusCode: status) },
                    javaScriptEnabled: false
                )
                .id(attempt)

                if isLoading && failure == nil {
                    ProgressView()
                }

                if let failure {
                    errorView(failure)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.backgroundGray)
    }

    /// When the start page fails to open (guide §13 "start page HTTP error → show connection failure and retry").
    /// The error body returned by the server is not rendered; only the status code is shown for reference.
    private func errorView(_ failure: LoadFailure) -> some View {
        VStack(spacing: 12) {
            Text("Couldn't open the issuer page.")
                .font(.pretendard(size: 15, weight: .semibold))
                .foregroundStyle(.black)

            Text(failure.statusCode.map { "The issuer server returned an error. (HTTP \($0))" }
                 ?? "Check your network connection and try again.")
                .font(.pretendard(size: 13, weight: .regular))
                .foregroundStyle(.customGray)
                .multilineTextAlignment(.center)

            Button {
                self.failure = nil
                isLoading = true
                attempt += 1
            } label: {
                Text("Retry")
                    .font(.pretendard(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(.customPrimary))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.backgroundGray)
    }

    struct LoadFailure {
        let statusCode: Int?
    }
}
