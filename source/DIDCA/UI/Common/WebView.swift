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

/// 범용 `WKWebView` 래퍼. 발급·검증 등 특정 흐름에 종속되지 않으며,
/// 웹 페이지 + JS 브리지가 필요한 어느 화면에서든 재사용한다.
/// - `messageHandlers`: 등록할 JS 메시지 핸들러 이름. 웹 페이지가
///   `window.webkit.messageHandlers.<name>.postMessage(...)` 를 호출하면 `onMessage` 로 전달된다.
/// - `onLoadingChanged`: 페이지 로딩 시작(true) / 완료·실패(false) 시 호출.
/// - `allowedHosts`: 비우면 http/https 를 host 제한 없이 허용(기존 동작). 채우면 그 host 로만 이동
///   가능하고 나머지 navigation 은 차단된다.
/// - `completionScheme` / `onCompletionURI`: 페이지가 앱으로 결과를 되돌리는 custom scheme.
///   해당 스킴 navigation 은 중단(cancel)하고 URL 을 콜백으로 넘긴다 — 외부 앱 실행으로 넘기지 않는다.
struct WebView: UIViewRepresentable {

    let url: URL
    var messageHandlers: [String] = []
    var onMessage: ((_ name: String, _ body: Any) -> Void)? = nil
    var onLoadingChanged: ((_ isLoading: Bool) -> Void)? = nil
    var allowedHosts: [String] = []
    var completionScheme: String? = nil
    var onCompletionURI: ((_ url: URL) -> Void)? = nil
    /// 페이지를 열지 못했을 때 호출 — 메인 프레임이 비-2xx 로 응답했거나(statusCode 동봉, 본문은
    /// 렌더링하지 않음) 전송 자체가 실패한 경우(nil). 앱이 취소한 navigation 은 실패로 보지 않는다.
    var onLoadFailure: ((_ statusCode: Int?) -> Void)? = nil
    /// 페이지 동작에 JS 가 필요할 때만 true. 필요 없는 화면은 꺼 둔다.
    var javaScriptEnabled: Bool = true
    /// true 면 페이지의 JS 다이얼로그(alert/confirm/prompt)를 팝업으로 띄우지 않고 즉시 기본값으로
    /// ack 한다(did-ca 파리티). 결과를 JS 브리지로 받는 발급 폼처럼, 페이지가 부수적으로 쏘는
    /// alert(예: 성공 직후의 잘못된 "실패" alert)가 흐름을 어지럽히지 않도록 할 때 사용한다.
    var silenceJSDialogs: Bool = false

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
        // 웹 인스펙터는 디버그 빌드에서만 — 배포 빌드에서 발급 화면을 들여다볼 수 없게 한다.
        #if DEBUG
        webView.isInspectable = true
        #else
        webView.isInspectable = false
        #endif
        webView.navigationDelegate = context.coordinator
        // JS 다이얼로그(alert/confirm/prompt)·새 창 요청을 앱이 직접 처리하기 위한 UI 델리게이트.
        // 미설정 시 alert 는 무시·confirm 은 false·prompt 는 nil·새 창은 먹통이 된다.
        webView.uiDelegate = context.coordinator
        webView.allowsLinkPreview = false
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    /// 등록한 메시지 핸들러를 해제해 coordinator ↔ WKWebView 사이 retain cycle 을 끊는다.
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
        /// 첫 메인 프레임 페이지가 정상(2xx)으로 뜬 적이 있는지 — 오류 가로채기를 시작 페이지로만
        /// 한정하는 데 쓴다. 재시도(`.id(attempt)`)로 웹뷰를 새로 만들면 coordinator 도 새로 생겨 초기화된다.
        private var hasLoadedMainFrame = false
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

        /// navigation 실패 처리. 순서가 중요하다.
        ///
        /// 1. **완료 스킴 복구** — 서버가 `302 Location: <completionScheme>://…` 로 완료를 알릴 때,
        ///    WebKit 이 그 리다이렉트를 `decidePolicyFor navigationAction` 에 태우지 않고 로드만
        ///    취소하는 경우가 있다(커스텀 스킴 리다이렉트). 그러면 화면도 그대로고 콜백도 없어
        ///    오퍼가 통째로 유실된다. 실패 error 에 실려오는 failing URL 이 완료 스킴이면 여기서
        ///    건져 정상 경로와 똑같이 콜백한다 — `decidePolicyFor` 로도 들어왔다면 호출 측이
        ///    중복을 막으므로(코디네이터의 처리중 플래그) 두 번 타도 무해하다.
        /// 2. 앱이 스스로 끊은 navigation(완료 스킴 가로채기·host 차단·비-2xx 취소)은 로딩 실패가 아니다.
        private func handleNavigationFailure(_ error: Error, phase: String) {
            let error = error as NSError
            // NSURLErrorDomain·WebKitErrorDomain 모두 실패 URL 을 이 키에 담는다.
            let failingURL = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL
            print("▶️[WEBVIEW]◀️ \(phase) domain=\(error.domain) code=\(error.code) "
                  + "failingURL=\(failingURL?.absoluteString ?? "nil")")

            if let completionScheme, let failingURL,
               failingURL.scheme?.lowercased() == completionScheme.lowercased() {
                onCompletionURI?(failingURL)
                return
            }

            let isCancelled = error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
            // WebKitErrorFrameLoadInterruptedByPolicyChange — decidePolicyFor 에서 .cancel 한 경우.
            let isPolicyCancel = error.domain == "WebKitErrorDomain" && error.code == 102
            guard !isCancelled, !isPolicyCancel else { return }
            onLoadFailure?(nil)
        }

        /// **시작 페이지**가 오류 응답(4xx·5xx)이면 본문을 렌더링하지 않고 앱 오류 화면으로 넘긴다 —
        /// 서버 오류 응답(JSON·스택트레이스 등)이 사용자에게 그대로 노출되지 않게 한다.
        ///
        /// 첫 페이지가 뜬 뒤로는 응답을 가로채지 않는다. 서버가 폼 검증 실패를 `400 + 폼 HTML`
        /// (필수 항목 안내 포함)로 돌려주기 때문에, 그걸 오류로 막으면 사용자가 무엇을 고쳐야 할지
        /// 볼 수 없다. 3xx 도 막지 않는다 — 발급 완료가 `openid-credential-offer://` 로의 302 redirect
        /// 로 오며, 그 결과는 `decidePolicyFor navigationAction` 또는 `handleNavigationFailure` 의
        /// 복구 경로가 잡는다.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            guard navigationResponse.isForMainFrame,
                  let response = navigationResponse.response as? HTTPURLResponse
            else {
                decisionHandler(.allow)
                return
            }
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

        /// 완료 스킴은 중단 후 콜백, http/https 는 (allowedHosts 가 있으면 그 host 만) 통과,
        /// 그 외 스킴(javascript:·file:·content:·외부 앱 등)은 모두 차단한다.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            let scheme = url.scheme?.lowercased()

            // 완료 응답 — navigation 을 실제로 중단하고 앱이 처리한다(외부 앱 실행으로 넘기지 않는다).
            if let completionScheme, scheme == completionScheme.lowercased() {
                decisionHandler(.cancel)
                onCompletionURI?(url)
                return
            }

            guard scheme == "http" || scheme == "https" else {
                // allowedHosts 를 쓰지 않는 기존 화면은 확장자 html 문서를 통과시키던 동작을 유지한다.
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

        // MARK: - WKUIDelegate (JS 다이얼로그 · 새 창)
        //
        // JS 의 네이티브 UI 요청을 OS 기본 팝업 대신 앱 커스텀 팝업(OverlayManager)으로 처리한다.
        // 각 completionHandler 는 반드시 정확히 한 번 호출해야 JS 가 멈추지 않는다 — 커스텀 팝업은
        // 버튼으로만 닫히고(backdrop 탭 비활성) 모든 버튼 액션이 핸들러를 호출하므로 보장된다.

        /// `window.alert()` → 단일 OK 버튼 팝업. OK 누르면 JS 진행.
        func webView(_ webView: WKWebView,
                     runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) {
            // did-ca 파리티: 발급 폼처럼 결과를 브리지로 받는 경우 페이지 alert 는 띄우지 않고 즉시 ack.
            if silenceJSDialogs { completionHandler(); return }
            OverlayManager.shared.showPopup(
                title: "Notification",
                message: message,
                primaryButtonTitle: "OK",
                primaryAction: { completionHandler() }
            )
        }

        /// `window.confirm()` → OK/Cancel 팝업. OK→true, Cancel→false.
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

        /// `window.prompt()` → 커스텀 팝업엔 입력칸이 없어 텍스트 편집은 불가.
        /// OK 는 JS 가 준 기본값을, Cancel 은 nil 을 반환한다(네이티브 prompt 의 OK=기본값 동작에 준함).
        /// 실제 자유 입력이 필요하면 PopupView 에 TextField 변형을 추가해야 한다.
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

        /// `window.open()` / `target="_blank"` — 별도 창 대신 현재 웹뷰에서 로드.
        /// 새 WKWebView 를 만들지 않으므로 nil 반환.
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
