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

enum CASConnection {
    static let host = URLs.CAS_URL
}

extension CASConnection {

    static func signup(request: ReqUserSignUp) async throws {
        let urlString = host + "/cas/api/v1/user/signup"
        try await HttpClient.sendPostRequest(urlString: urlString, request: request)
    }

    static func getWalletTokenData(request: WalletTokenSeed) async throws -> WalletTokenData {
        let urlString = host + "/cas/api/v1/request-wallet-tokendata"
        return try await HttpClient.sendPostRequest(urlString: urlString, request: request)
    }

    /// CAS 가 서명·인증한 앱 정보 조회 (ServerTokenSeed 구성에 필요).
    static func requestAttestedAppInfo() async throws -> AttestedAppInfo {
        let urlString = host + "/cas/api/v1/request-attested-appinfo"
        let walletId = Properties.getWalletId() ?? Preference.getUserId() ?? ""
        let request = RequestAttestedAppInfo(appId: walletId)
        return try await HttpClient.sendPostRequest(urlString: urlString, request: request)
    }
}

extension CASConnection {

    struct ReqUserSignUp: Jsonable {
        var userId: String
        var walletId: String
    }
}
