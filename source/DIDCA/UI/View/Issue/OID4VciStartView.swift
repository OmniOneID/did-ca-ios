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

/// OID4VCI 사용자 클레임 입력 WebView (연동 가이드 §6·§11).
///
/// Issuer 가 제공하는 입력 화면을 띄우기만 한다 — JS 브리지를 등록하지 않고, 입력값·DID 를
/// 앱으로 받아오지 않는다. 완료는 오직 `openid-credential-offer://` navigation 으로만 오며,
/// 그 처리(파싱·검증·중복 방지·모달 닫기)는 코디네이터가 맡는다.
///
/// 보안 설정: JS 비활성(서버 화면이 JS 를 쓰지 않음), Issuer host 밖 이동 차단, 완료 스킴 외
/// 커스텀 스킴·외부 앱 실행 차단, SSL 오류 우회 없음(챌린지 미처리 = 기본 거부).
struct OID4VciStartView: View {

    let url: URL
    /// 허용 host — 시작 URL 의 host. 같은 Issuer 화면과 form submit 만 오간다.
    let allowedHost: String
    /// X 버튼으로 닫음 → 발급 취소.
    let onClose: () -> Void
    /// `openid-credential-offer://` navigation 가로챔 → 코디네이터가 완료 처리.
    let onCompletionURI: (URL) -> Void

    @State private var isLoading = true
    // 로딩 실패 상태 — 값이 있으면 웹 콘텐츠 대신 오류 화면을 덮는다. 연관값은 HTTP 상태 코드
    // (전송 자체가 실패했으면 nil).
    @State private var failure: LoadFailure? = nil
    // 재시도 카운터. 값이 바뀌면 WebView 를 새로 만들어 시작 URL 을 다시 연다.
    // 회전·화면 재생성으로는 증가하지 않으므로 서버 발급 세션이 임의로 새로 생기지 않는다 —
    // 사용자가 명시적으로 재시도할 때만 새 세션이다.
    @State private var attempt = 0

    var body: some View {
        VStack(spacing: 0) {
            // 모달이므로 좌측은 X — 닫으면 발급 취소.
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

    /// 시작 페이지를 열지 못했을 때 (가이드 §13 "시작 페이지 HTTP 오류 → 연결 실패 표시 및 재시도").
    /// 서버가 내려준 오류 본문은 렌더링하지 않고 상태 코드만 참고 표시한다.
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
