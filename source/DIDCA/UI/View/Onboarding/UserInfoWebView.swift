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

/// The user passed by the registration web view via `onCompletedUserInfoUpload`.
struct RegisteredUser {
    let userId: String
    /// Exactly as the server sent it — the app doesn't combine First / Last Name. May be empty.
    let userName: String
}

/// Onboarding Step 1 user registration web view (`DEMO_URL/addUserInfo`).
///
/// The app draws only the top bar, loading and dialogs; the input form, validation and submission are up to the server page.
/// Results arrive through the JS bridge the page promises (same names as did-ca-ios `UserRegWebViewController`).
/// - `onCompletedUserInfoUpload` (JSON string `{userId, username}`) → `onRegistered` after OK on the success message popup
/// - `onFailedUserInfoUpload` → "Registration failed" popup, web view kept
/// - `showAlert` (string) → message the page sends right after the result. Only the success message is shown as a popup;
///   "Error: …" messages are dropped, since the design spec says not to expose debug messages.
struct UserInfoWebView: View {

    let url: URL
    /// X button or OK on the load-failure popup — closes the modal and returns to Step 1.
    let onClose: () -> Void
    let onRegistered: (RegisteredUser) -> Void
    /// Server settings link on the load-failure popup.
    let onServerSettings: () -> Void

    @State private var isLoading = true
    @State private var loadFailed = false
    // Ensures the lock popup appears only once even if the registration-complete callback arrives twice.
    @State private var finished = false
    // User whose registration is done, waiting for the success message (showAlert). Handed off on message popup OK or wait timeout.
    @State private var pendingUser: RegisteredUser?
    // Success message popup is showing — in this case popup OK, not the wait timeout, hands off the user.
    @State private var showingSuccessAlert = false

    private static let completedHandler = "onCompletedUserInfoUpload"
    private static let failedHandler = "onFailedUserInfoUpload"
    private static let alertHandler = "showAlert"
    /// The page sends showAlert in the same execution flow right after the completion callback. Even for a page that sends no
    /// message, once this time passes it proceeds without one so the flow doesn't stall.
    private static let alertWait: Duration = .seconds(1)

    var body: some View {
        VStack(spacing: 0) {
            // It's a modal, so the left button is X — closing returns to Step 1 without registering.
            NavBar(title: "Register User", icon: .icCloseWhite, action: onClose)

            ZStack {
                WebView(
                    url: url,
                    messageHandlers: [Self.completedHandler, Self.failedHandler, Self.alertHandler],
                    onMessage: handleMessage,
                    onLoadingChanged: { isLoading = $0 },
                    onLoadFailure: { _ in showLoadFailure() },
                    // The page's JS dialogs (alert·confirm·prompt) are hidden across the whole web view.
                    // The success message comes via the showAlert bridge, not alert.
                    silenceJSDialogs: true,
                    // A page that never answers is a load failure too.
                    firstLoadTimeout: .seconds(15)
                )
                // On load failure, show only a popup over a blank screen instead of the server error body (02b).
                .opacity(loadFailed ? 0 : 1)

                if isLoading && !loadFailed {
                    ProgressView()
                }
            }
            .background(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.backgroundGray)
    }

    private func handleMessage(name: String, body: Any) {
        if name == Self.alertHandler {
            handleAlert(body)
            return
        }
        guard !finished else { return }
        guard name == Self.completedHandler, let user = Self.parse(body) else {
            // Failure callback, or a completion callback whose userId can't be read — nothing to save, so it's the same failure.
            OverlayManager.shared.showPopup(
                title: "Registration failed",
                message: "We couldn't complete your registration. Please try again.",
                primaryButtonTitle: "OK"
            )
            return
        }
        finished = true
        // Showing the lock popup right away would be overwritten by the success message popup that follows — show the message
        // first and hand off after OK. If no message arrives, hand off after the wait timeout.
        pendingUser = user
        Task {
            try? await Task.sleep(for: Self.alertWait)
            if !showingSuccessAlert { deliverPendingUser() }
        }
    }

    /// Page message. Only the message right after successful registration is shown — the failure-side "Error: …" is a 2.0
    /// debug message and isn't shown. Failure guidance is handled by onFailedUserInfoUpload's "Registration failed".
    private func handleAlert(_ body: Any) {
        guard pendingUser != nil, !showingSuccessAlert,
              let message = body as? String, !message.isEmpty,
              !message.hasPrefix("Error")
        else { return }
        showingSuccessAlert = true
        OverlayManager.shared.showPopup(
            title: "Notification",
            message: message,
            primaryButtonTitle: "OK",
            // PopupView calls the button action and then closes the popup — handing off right here would let that close wipe
            // the lock popup that appears next. Hand off after it closes (next turn).
            primaryAction: { Task { deliverPendingUser() } }
        )
    }

    private func deliverPendingUser() {
        guard let user = pendingUser else { return }
        pendingUser = nil
        onRegistered(user)
    }

    /// Couldn't load the page. Treated as server unreachable and the Server settings link is attached.
    /// Non-2xx responses for the start page also come here — usually a wrong address, so the same guidance fits.
    private func showLoadFailure() {
        guard !loadFailed else { return }
        loadFailed = true
        OverlayManager.shared.showErrorPopup(
            title: "Error",
            error: URLError(.cannotConnectToHost),
            primaryAction: onClose,
            onServerSettings: onServerSettings
        )
    }

    /// The page passes JSON as a string (same as did-ca-ios). Also reads it if passed as an object.
    private static func parse(_ body: Any) -> RegisteredUser? {
        let json: [String: Any]?
        if let string = body as? String, let data = string.data(using: .utf8) {
            json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        } else {
            json = body as? [String: Any]
        }
        guard let userId = json?["userId"] as? String, !userId.isEmpty else { return nil }
        return RegisteredUser(userId: userId, userName: json?["username"] as? String ?? "")
    }
}
