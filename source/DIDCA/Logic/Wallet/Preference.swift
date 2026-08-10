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

// walletId 는 DIDWalletSDK 의 Properties 가 관리 (requestRegisterWallet 시점에 set).
// userRegistered 는 step3 (onboarding 종료) 완료 여부 — splash 의 main 진입 분기에 사용.
enum PreferenceKey: String, CaseIterable {
    case userId
    case userRegistered
    // proxy 모드로 발급한 VC 의 [vcId: 발급자 endpoint] 매핑 — 폐기 시 해당 VC 를
    // 어느 발급자 호스트로 보낼지 vcId 로 찾으려고 보관.
    case issuerEndpoints
}

nonisolated enum Preference {

    private static let defaults = UserDefaults.standard

    static func getUserId() -> String? {
        defaults.string(forKey: PreferenceKey.userId.rawValue)
    }

    static func setUserId(_ userId: String) {
        defaults.setValue(userId, forKey: PreferenceKey.userId.rawValue)
    }

    static func clearUserId() {
        defaults.removeObject(forKey: PreferenceKey.userId.rawValue)
    }

    /// proxy 발급 VC 의 발급자 endpoint 조회 (폐기 라우팅용). 직접(TAS) 발급분이면 nil.
    static func getIssuerEndpoint(forVcId vcId: String) -> String? {
        let map = defaults.dictionary(forKey: PreferenceKey.issuerEndpoints.rawValue) as? [String: String]
        return map?[vcId]
    }

    /// proxy 발급 직후 [vcId: endpoint] 매핑에 한 건 추가.
    static func setIssuerEndpoint(_ endpoint: String, forVcId vcId: String) {
        var map = (defaults.dictionary(forKey: PreferenceKey.issuerEndpoints.rawValue) as? [String: String]) ?? [:]
        map[vcId] = endpoint
        defaults.setValue(map, forKey: PreferenceKey.issuerEndpoints.rawValue)
    }

    /// 폐기 완료 후 [vcId: endpoint] 매핑에서 해당 VC 제거.
    static func removeIssuerEndpoint(forVcId vcId: String) {
        guard var map = defaults.dictionary(forKey: PreferenceKey.issuerEndpoints.rawValue) as? [String: String] else {
            return
        }
        map.removeValue(forKey: vcId)
        defaults.setValue(map, forKey: PreferenceKey.issuerEndpoints.rawValue)
    }

    static func isUserRegistered() -> Bool {
        defaults.bool(forKey: PreferenceKey.userRegistered.rawValue)
    }

    static func setUserRegistered(_ value: Bool) {
        defaults.setValue(value, forKey: PreferenceKey.userRegistered.rawValue)
    }

    static func reset() {
        for key in PreferenceKey.allCases {
            defaults.removeObject(forKey: key.rawValue)
        }
    }
}
