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

/// 발급 추가정보 입력 웹 폼 (`DEMO_URL/addVcInfo`).
/// 범용 `WebView` 를 조합하고, addVcInfo 페이지가 약속한 JS 콜백만 여기서 결과로 매핑한다.
/// - `onCompletedAddVcUpload` → 업로드 성공 → `onResult(true)`
/// - `onFailedAddVcUpload`    → 업로드 실패 → `onResult(false)`
/// - X 버튼으로 닫으면        → `onResult(false)`
struct IssueWebFormView: View {

    let url: URL
    /// 폼 완료 여부. true 면 발급 진행, false 면 발급 중단.
    let onResult: (Bool) -> Void

    @State private var isLoading = true

    private static let completedHandler = "onCompletedAddVcUpload"
    private static let failedHandler = "onFailedAddVcUpload"

    var body: some View {
        VStack(spacing: 0) {
            // 모달이므로 좌측은 X — 닫으면 폼 취소(발급 중단).
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
                    // 발급 결과는 위 JS 브리지가 권위. 페이지가 부수적으로 쏘는 alert/confirm/prompt 는
                    // 팝업으로 띄우지 않고 즉시 ack 한다 — did-ca 와 동일한 동작.
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
