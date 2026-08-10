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

struct ServerErrorResponse: Jsonable {
    let code: String
    let description: String
}

enum ServerError: Error, LocalizedError {
    case message(ServerErrorResponse)
    var errorDescription: String? {
        switch self {
        case .message(let res): return res.description
        }
    }
}

enum HttpClientError: Error, LocalizedError {
    /// 서버가 준 id/DID 등이 URL 로 파싱되지 않음 (공백·제어문자 등).
    case invalidURL(String)
    var errorDescription: String? {
        switch self {
        case .invalidURL(let s): return "Invalid request URL: \(s)"
        }
    }
}

private extension Encodable {
    func asQueryItems() -> [URLQueryItem] {
        guard let data = try? JSONEncoder().encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return dict.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
    }
}

enum HttpClient {

    static func sendGetRequest<T: Jsonable>(urlString: String,
                                            request: Jsonable? = nil) async throws -> T {
        guard var components = URLComponents(string: urlString) else {
            throw HttpClientError.invalidURL(urlString)
        }
        if let request = request {
            components.queryItems = request.asQueryItems()
        }
        guard let url = components.url else {
            throw HttpClientError.invalidURL(urlString)
        }

        let (response, statusCode) = try await CommunicationClient.sendRequest(
            urlString: url.absoluteString,
            httpMethod: .GET
        )

        switch statusCode {
        case 200...299:
            return try T.init(from: response)
        default:
            let error = try ServerErrorResponse.init(from: response)
            throw ServerError.message(error)
        }
    }

    static func sendPostRequest<T: Jsonable>(urlString: String,
                                             request: Jsonable? = nil) async throws -> T {
        let jsonData: Data? = try request?.toJsonData()

        let (response, statusCode) = try await CommunicationClient.sendRequest(
            urlString: urlString,
            requestJsonData: jsonData
        )

        switch statusCode {
        case 200...299:
            return try T.init(from: response)
        default:
            let error = try ServerErrorResponse.init(from: response)
            throw ServerError.message(error)
        }
    }

    static func sendPostRequest(urlString: String,
                                request: Jsonable? = nil) async throws {
        let jsonData: Data? = try request?.toJsonData()

        let (response, statusCode) = try await CommunicationClient.sendRequest(
            urlString: urlString,
            requestJsonData: jsonData
        )

        switch statusCode {
        case 200...299:
            return
        default:
            let error = try ServerErrorResponse.init(from: response)
            throw ServerError.message(error)
        }
    }
}
