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
import WebKit

/// General-purpose `WKWebView` wrapper. Not tied to any specific flow such as issuance or verification;
/// reused by any screen that needs a web page + JS bridge.
/// - `messageHandlers`: names of JS message handlers to register. When the web page calls
///   `window.webkit.messageHandlers.<name>.postMessage(...)`, it is delivered to `onMessage`.
/// - `onLoadingChanged`: called when page loading starts (true) / finishes or fails (false).
/// - `allowedHosts`: if empty, http/https is allowed with no host restriction (existing behavior). If set,
///   navigation is only possible to those hosts and all other navigation is blocked.
/// - `completionScheme` / `onCompletionURI`: custom scheme by which the page returns a result to the app.
///   Navigation to that scheme is cancelled and the URL is passed to the callback — not handed off to launch an external app.
struct WebView: UIViewRepresentable {

    let url: URL
    var messageHandlers: [String] = []
    var onMessage: ((_ name: String, _ body: Any) -> Void)? = nil
    var onLoadingChanged: ((_ isLoading: Bool) -> Void)? = nil
    var allowedHosts: [String] = []
    var completionScheme: String? = nil
    var onCompletionURI: ((_ url: URL) -> Void)? = nil
    /// Called when the page could not be opened — the main frame responded with a non-2xx (statusCode included,
    /// body not rendered) or the transfer itself failed (nil). Navigation cancelled by the app is not treated as failure.
    var onLoadFailure: ((_ statusCode: Int?) -> Void)? = nil
    /// true only when the page needs JS to function. Leave it off for screens that don't.
    var javaScriptEnabled: Bool = true
    /// If true, the page's JS dialogs (alert/confirm/prompt) are not shown as popups and are acked immediately
    /// with the default value (did-ca parity). Used, like the issuance form whose result comes over the JS bridge,
    /// so that incidental alerts fired by the page (e.g. a bogus "failure" alert right after success) don't disrupt the flow.
    var silenceJSDialogs: Bool = false
    /// If set, the start page must produce a response or a failure within this time, otherwise `onLoadFailure(nil)`
    /// fires (a connect timeout). Some loads never call back at all — WebKit silently refuses restricted ports
    /// such as `:1` — and would otherwise leave a blank page up indefinitely.
    var firstLoadTimeout: Duration? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onMessage: onMessage,
                    onLoadingChanged: onLoadingChanged,
                    silenceJSDialogs: silenceJSDialogs,
                    allowedHosts: allowedHosts,
                    completionScheme: completionScheme,
                    onCompletionURI: onCompletionURI,
                    onLoadFailure: onLoadFailure)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        for name in messageHandlers {
            contentController.add(context.coordinator, name: name)
        }
        context.coordinator.registeredHandlers = messageHandlers

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = javaScriptEnabled
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        // Web inspector only in debug builds — so the issuance screen can't be inspected in release builds.
        #if DEBUG
        webView.isInspectable = true
        #else
        webView.isInspectable = false
        #endif
        webView.navigationDelegate = context.coordinator
        // UI delegate so the app itself handles JS dialogs (alert/confirm/prompt) and new-window requests.
        // If unset, alert is ignored, confirm returns false, prompt returns nil, and new windows do nothing.
        webView.uiDelegate = context.coordinator
        webView.allowsLinkPreview = false
        webView.load(URLRequest(url: url))
        if let firstLoadTimeout {
            context.coordinator.startFirstLoadWatchdog(after: firstLoadTimeout)
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    /// Unregisters the message handlers to break the retain cycle between the coordinator and WKWebView.
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        let controller = webView.configuration.userContentController
        for name in coordinator.registeredHandlers {
            controller.removeScriptMessageHandler(forName: name)
        }
        controller.removeAllUserScripts()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        private let onMessage: ((String, Any) -> Void)?
        private let onLoadingChanged: ((Bool) -> Void)?
        private let silenceJSDialogs: Bool
        private let allowedHosts: [String]
        private let completionScheme: String?
        private let onCompletionURI: ((URL) -> Void)?
        private let onLoadFailure: ((Int?) -> Void)?
        /// Whether the first main-frame page has ever loaded successfully (2xx) — used to limit error interception
        /// to the start page only. Recreating the web view on retry (`.id(attempt)`) also creates a new coordinator, resetting it.
        private var hasLoadedMainFrame = false
        /// Whether the start page has produced anything — a main-frame response or a failure. The first-load watchdog
        /// only fires while this is still false.
        private var firstLoadSettled = false
        var registeredHandlers: [String] = []

        init(onMessage: ((String, Any) -> Void)?,
             onLoadingChanged: ((Bool) -> Void)?,
             silenceJSDialogs: Bool,
             allowedHosts: [String],
             completionScheme: String?,
             onCompletionURI: ((URL) -> Void)?,
             onLoadFailure: ((Int?) -> Void)?) {
            self.onMessage = onMessage
            self.onLoadingChanged = onLoadingChanged
            self.silenceJSDialogs = silenceJSDialogs
            self.allowedHosts = allowedHosts
            self.completionScheme = completionScheme
            self.onCompletionURI = onCompletionURI
            self.onLoadFailure = onLoadFailure
        }

        func startFirstLoadWatchdog(after timeout: Duration) {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self, !self.firstLoadSettled else { return }
                self.firstLoadSettled = true
                self.onLoadingChanged?(false)
                self.onLoadFailure?(nil)
            }
        }

        // MARK: - WKScriptMessageHandler

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            onMessage?(message.name, message.body)
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            onLoadingChanged?(true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoadingChanged?(false)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onLoadingChanged?(false)
            handleNavigationFailure(error, phase: "didFail")
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            onLoadingChanged?(false)
            handleNavigationFailure(error, phase: "didFailProvisional")
        }

        /// Handles navigation failures. Order matters.
        ///
        /// 1. **Completion-scheme recovery** — when the server signals completion with `302 Location: <completionScheme>://…`,
        ///    WebKit may not route that redirect through `decidePolicyFor navigationAction` and simply cancel
        ///    the load (custom-scheme redirect). The screen then stays as is with no callback, and the
        ///    offer is lost entirely. If the failing URL carried in the error is the completion scheme, it is
        ///    recovered here and called back exactly like the normal path — if it also came through `decidePolicyFor`,
        ///    the caller prevents duplicates (the coordinator's in-progress flag), so going through both is harmless.
        /// 2. Navigation the app cut off itself (completion-scheme interception, host block, non-2xx cancel) is not a load failure.
        private func handleNavigationFailure(_ error: Error, phase: String) {
            firstLoadSettled = true
            let error = error as NSError
            // Both NSURLErrorDomain and WebKitErrorDomain put the failing URL under this key.
            let failingURL = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL
            print("▶️[WEBVIEW]◀️ \(phase) domain=\(error.domain) code=\(error.code) "
                  + "failingURL=\(failingURL?.absoluteString ?? "nil")")

            if let completionScheme, let failingURL,
               failingURL.scheme?.lowercased() == completionScheme.lowercased() {
                onCompletionURI?(failingURL)
                return
            }

            let isCancelled = error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
            // WebKitErrorFrameLoadInterruptedByPolicyChange — the case where decidePolicyFor returned .cancel.
            let isPolicyCancel = error.domain == "WebKitErrorDomain" && error.code == 102
            guard !isCancelled, !isPolicyCancel else { return }
            onLoadFailure?(nil)
        }

        /// If the **start page** is an error response (4xx/5xx), its body is not rendered and the app error screen takes over —
        /// so server error responses (JSON, stack traces, etc.) are never exposed to the user as is.
        ///
        /// After the first page has loaded, responses are not intercepted. The server returns form validation failures as
        /// `400 + form HTML` (including required-field hints), so blocking those as errors would hide what the user needs
        /// to fix. 3xx is not blocked either — issuance completion arrives as a 302 redirect to `openid-credential-offer://`,
        /// and that result is caught by `decidePolicyFor navigationAction` or the recovery path in
        /// `handleNavigationFailure`.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            guard navigationResponse.isForMainFrame,
                  let response = navigationResponse.response as? HTTPURLResponse
            else {
                decisionHandler(.allow)
                return
            }
            firstLoadSettled = true
            guard response.statusCode >= 400, !hasLoadedMainFrame else {
                if (200...299).contains(response.statusCode) {
                    hasLoadedMainFrame = true
                }
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            onLoadFailure?(response.statusCode)
        }

        /// The completion scheme is cancelled then called back, http/https passes (only the allowedHosts if set),
        /// and every other scheme (javascript:, file:, content:, external apps, etc.) is blocked.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            let scheme = url.scheme?.lowercased()

            // Completion response — actually cancel the navigation and let the app handle it (not handed off to launch an external app).
            if let completionScheme, scheme == completionScheme.lowercased() {
                decisionHandler(.cancel)
                onCompletionURI?(url)
                return
            }

            guard scheme == "http" || scheme == "https" else {
                // Existing screens that don't use allowedHosts keep the behavior of letting .html documents through.
                let isHtml = url.absoluteString.hasSuffix("html")
                decisionHandler(allowedHosts.isEmpty && isHtml ? .allow : .cancel)
                return
            }

            guard !allowedHosts.isEmpty else {
                decisionHandler(.allow)
                return
            }
            let host = url.host?.lowercased() ?? ""
            decisionHandler(allowedHosts.contains { $0.lowercased() == host } ? .allow : .cancel)
        }

        // MARK: - WKUIDelegate (JS dialogs · new windows)
        //
        // JS native UI requests are handled with the app's custom popup (OverlayManager) instead of the OS default popup.
        // Each completionHandler must be called exactly once or JS stalls — this is guaranteed because the custom popup
        // closes only through a button action — a backdrop tap runs the default button's action — and every
        // button action calls the handler.

        /// `window.alert()` → single OK-button popup. Tapping OK resumes JS.
        func webView(_ webView: WKWebView,
                     runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) {
            // did-ca parity: when the result comes over the bridge, as in the issuance form, the page alert is not shown and is acked immediately.
            if silenceJSDialogs { completionHandler(); return }
            OverlayManager.shared.showPopup(
                title: "Notification",
                message: message,
                primaryButtonTitle: "OK",
                primaryAction: { completionHandler() }
            )
        }

        /// `window.confirm()` → OK/Cancel popup. OK→true, Cancel→false.
        func webView(_ webView: WKWebView,
                     runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) {
            if silenceJSDialogs { completionHandler(false); return }
            OverlayManager.shared.showPopup(
                title: "Notification",
                message: message,
                primaryButtonTitle: "OK",
                primaryAction: { completionHandler(true) },
                secondaryButtonTitle: "Cancel",
                secondaryAction: { completionHandler(false) }
            )
        }

        /// `window.prompt()` → the custom popup has no input field, so text editing isn't possible.
        /// OK returns the default value JS supplied and Cancel returns nil (mirroring native prompt's OK = default value behavior).
        /// If real free-form input is needed, a TextField variant must be added to PopupView.
        func webView(_ webView: WKWebView,
                     runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            if silenceJSDialogs { completionHandler(nil); return }
            OverlayManager.shared.showPopup(
                title: "Notification",
                message: prompt,
                primaryButtonTitle: "OK",
                primaryAction: { completionHandler(defaultText ?? "") },
                secondaryButtonTitle: "Cancel",
                secondaryAction: { completionHandler(nil) }
            )
        }

        /// `window.open()` / `target="_blank"` — loads in the current web view instead of a separate window.
        /// Returns nil since no new WKWebView is created.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
