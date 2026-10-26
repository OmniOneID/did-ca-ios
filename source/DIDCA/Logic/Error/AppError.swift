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

// Normalizes user-facing errors by where they originate. Mapped to the design spec common items COM-02/03/04.
//   .server  : non-2xx response — preserves backend code/description. (COM-04) Accepts both `HttpClient`'s `ServerError`
//              and the `CommunicationSDKError` that SDK `CommunicationClient` throws carrying the raw body.
//   .network : URLError — transport-layer failures such as no connection, timeout, unreachable. Shows a fixed message. (COM-02)
//   .other   : everything else (DIDWalletSDK errors, TokenGeneratorError, DecodingError, NSError validation, etc.). (COM-03)
//              Shown via Swift's default string representation, so the enum case / domain is visible as-is.
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
            // The SDK wraps a non-2xx body in a string and throws — if it's a backend code/description, extract and use it.
            self = .server(code: response.code, description: response.description)
        } else if error is URLError {
            self = .network
        } else {
            self = .other(error)
        }
    }

    /// If the response body carried in `CommunicationSDKError.message` is in an error format, parses and returns it.
    /// SDK-internal errors (URL errors, parameter errors, etc.) have no body, so nil → falls through to `.other`.
    ///
    /// **There are two formats.** The OpenDID backend uses `{code, description}`, but the OID4VCI endpoints
    /// (`/token` · `/credential` · `/nonce`) are an OAuth 2.0 server and answer with `{error, error_description}` (RFC 6749 §5.2).
    /// Failing to read the latter discards the server's failure reason entirely — this is why the tx_code error's
    /// `invalid_grant` description didn't appear on screen (COM-04 · TXC-E-01).
    private static func serverResponse(embeddedIn error: CommunicationSDKError) -> ServerErrorResponse? {
        guard let data = error.message.data(using: .utf8) else { return nil }
        if let response = try? ServerErrorResponse(from: data) {
            return response
        }
        return oauthResponse(from: data)
    }

    /// OAuth 2.0 error response → `ServerErrorResponse`.
    ///
    /// **Returns nil** if `error_description` is missing — `error` is a machine code (`invalid_grant`),
    /// not a sentence to show the user. This is exactly the branch where the design spec says to use the fallback
    /// "when the response has no message", so it falls through to `.other` here to let the caller's fallback apply.
    private static func oauthResponse(from data: Data) -> ServerErrorResponse? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["error"] as? String, !code.isEmpty,
              // The verifier's OID4VP error response writes the same format in camelCase (`errorDescription`).
              let description = (json["error_description"] ?? json["errorDescription"]) as? String,
              !description.isEmpty
        else {
            return nil
        }
        return ServerErrorResponse(code: code, description: description)
    }

    /// Used by callers that hold the response body directly, to preserve the server's failure reason.
    ///
    /// Paths through SDK `CommunicationClient` get the body carried in `CommunicationSDKError`, but
    /// on paths that receive the response as-is (OID4VP submission) it isn't kept anywhere unless the caller keeps it.
    /// With only the status code left, "why it was rejected" is lost entirely, so the same two formats are read here —
    /// OpenDID `{code, description}` and OAuth 2.0 `{error, error_description}`.
    /// If it's neither, nil, so the caller's status-code fallback applies.
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
    /// Error popup. If a fallback is given, that fallback text is shown instead only for SDK/unknown errors (.other — the raw
    /// string isn't user-friendly) (e.g. VC-E-01 "Failed to delete. Try again."). Server response errors (.server) always
    /// prefer the backend message, and network errors (.network) the COM-02 fixed message (fallback ignored).
    /// - parameter onServerSettings: if given, attaches a `Server settings` link at the bottom **only when the server is
    ///   unreachable (.network — COM-02 family)** (DLG-05 · ONB-E-01 · ONB-E-04). SDK-internal errors (COM-03) and
    ///   server response errors (COM-04) occur after reaching the server, so the address isn't the cause and no link is shown.
    @MainActor
    func showErrorPopup(title: String,
                        error: Error,
                        fallback: String? = nil,
                        primaryAction: @escaping () -> Void = {},
                        onServerSettings: (() -> Void)? = nil) {
        let appError = AppError(error)
        let message: String
        if case .other = appError, let fallback {
            message = fallback
        } else {
            message = appError.message
        }
        var link: (() -> Void)?
        if case .network = appError { link = onServerSettings }
        showPopup(
            title: title,
            message: message,
            primaryButtonTitle: "OK",
            primaryAction: primaryAction,
            linkButtonTitle: link == nil ? nil : "Server settings",
            linkAction: link
        )
    }
}
