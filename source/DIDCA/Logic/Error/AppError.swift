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


import Foundation
import DIDWalletSDK

// 사용자에게 보여줄 에러를 발생 위치 기준으로 정규화. 설계서 공통 명세 COM-02/03/04 와 매핑.
//   .server  : non-2xx 응답 — 백엔드 code/description 보존. (COM-04) `HttpClient` 의 `ServerError` 와,
//              SDK `CommunicationClient` 가 body 원문을 담아 던지는 `CommunicationSDKError` 를 모두 받는다.
//   .network : URLError — 네트워크 미연결·타임아웃·도달 불가 등 전송 계층 실패. 고정 문구 노출. (COM-02)
//   .other   : 그 외 모두 (DIDWalletSDK 에러, TokenGeneratorError, DecodingError, NSError validation 등). (COM-03)
//              Swift 의 기본 문자열 표현으로 노출되므로 enum case / domain 이 그대로 보임.
enum AppError: Error {
    case server(code: String, description: String)
    case network
    case other(Error)

    init(_ error: Error) {
        if let appError = error as? AppError {
            self = appError
        } else if let serverError = error as? ServerError,
                  case .message(let response) = serverError {
            self = .server(code: response.code, description: response.description)
        } else if let sdkError = error as? CommunicationSDKError,
                  let response = Self.serverResponse(embeddedIn: sdkError) {
            // SDK 는 non-2xx body 를 문자열로 감싸 던진다 — 백엔드 code/description 이면 꺼내 쓴다.
            self = .server(code: response.code, description: response.description)
        } else if error is URLError {
            self = .network
        } else {
            self = .other(error)
        }
    }

    /// `CommunicationSDKError.message` 에 실린 응답 body 가 에러 형식이면 파싱해 돌려준다.
    /// SDK 자체 오류(URL 오류·파라미터 오류 등)는 body 가 없으므로 nil → `.other` 로 떨어진다.
    ///
    /// **형식이 둘이다.** OpenDID 백엔드는 `{code, description}` 이지만, OID4VCI 엔드포인트
    /// (`/token`·`/credential`·`/nonce`)는 OAuth 2.0 서버라 `{error, error_description}`(RFC 6749 §5.2)로
    /// 답한다. 뒤엣것을 못 읽으면 서버가 준 실패 이유가 통째로 버려진다 — tx_code 오류의
    /// `invalid_grant` 설명이 화면에 못 뜨던 원인이다(COM-04·TXC-E-01).
    private static func serverResponse(embeddedIn error: CommunicationSDKError) -> ServerErrorResponse? {
        guard let data = error.message.data(using: .utf8) else { return nil }
        if let response = try? ServerErrorResponse(from: data) {
            return response
        }
        return oauthResponse(from: data)
    }

    /// OAuth 2.0 오류 응답 → `ServerErrorResponse`.
    ///
    /// `error_description` 이 없으면 **nil 을 돌려준다** — `error` 는 기계용 코드(`invalid_grant`)이지
    /// 사용자에게 보일 문장이 아니다. 설계서가 "응답에 메시지가 없을 경우" 폴백을 쓰라고 하는 갈래가
    /// 정확히 이 경우이므로, 여기서 `.other` 로 떨어뜨려 호출측 폴백이 살아나게 한다.
    private static func oauthResponse(from data: Data) -> ServerErrorResponse? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["error"] as? String, !code.isEmpty,
              // verifier 의 OID4VP 오류 응답은 같은 형식을 camelCase 로 적는다(`errorDescription`).
              let description = (json["error_description"] ?? json["errorDescription"]) as? String,
              !description.isEmpty
        else {
            return nil
        }
        return ServerErrorResponse(code: code, description: description)
    }

    /// 응답 body 를 직접 쥔 호출측이 서버가 준 실패 이유를 살릴 때 쓴다.
    ///
    /// SDK `CommunicationClient` 를 거치는 경로는 body 가 `CommunicationSDKError` 에 실려 오지만,
    /// 응답을 그대로 돌려받는 경로(OID4VP 제출)는 호출측이 버리지 않는 한 아무 데도 남지 않는다.
    /// 상태코드만 남으면 "왜 거절됐는지"가 통째로 사라지므로 여기서 같은 두 형식을 그대로 읽는다 —
    /// OpenDID `{code, description}` 과 OAuth 2.0 `{error, error_description}`.
    /// 어느 쪽도 아니면 nil 이라 호출측의 상태코드 폴백이 살아난다.
    static func server(from data: Data) -> AppError? {
        if let response = try? ServerErrorResponse(from: data) {
            return .server(code: response.code, description: response.description)
        }
        if let response = oauthResponse(from: data) {
            return .server(code: response.code, description: response.description)
        }
        return nil
    }

    var message: String {
        switch self {
        case .server(let code, let description):
            return "[\(code)] \(description)"
        case .network:
            return "The network connection is unstable. Please try again later."
        case .other(let error):
            return "\(error)"
        }
    }
}

extension OverlayManager {
    /// 에러 팝업. fallback 이 주어지면 SDK/unknown 오류(.other — raw 문자열이 사용자 친화적이지 않음)에 한해
    /// 그 fallback 문구를 대신 노출한다 (예: VC-E-01 "Failed to delete. Try again."). 서버 응답 오류(.server)는
    /// 백엔드 메시지를, 네트워크 오류(.network)는 COM-02 고정 문구를 항상 우선한다 (fallback 무시).
    @MainActor
    func showErrorPopup(title: String, error: Error, fallback: String? = nil, primaryAction: @escaping () -> Void = {}) {
        let appError = AppError(error)
        let message: String
        if case .other = appError, let fallback {
            message = fallback
        } else {
            message = appError.message
        }
        showPopup(
            title: title,
            message: message,
            primaryButtonTitle: "OK",
            primaryAction: primaryAction
        )
    }
}
