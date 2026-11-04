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

// walletId is managed by DIDWalletSDK's Properties (set at requestRegisterWallet).
// userRegistered is whether step3 (end of onboarding) is complete — used by splash to branch into main.
enum PreferenceKey: String, CaseIterable {
    // Values passed via the JS bridge by the onboarding Step 1 user registration webview (DEMO_URL/addUserInfo).
    // userId is used for the wallet token and KYC; userName for the Settings display and the issuance web page.
    case userId
    case userName
    // Whether user binding (bindUser, plus registerLock if lock was chosen) is complete. Kept separately so that if the
    // app is killed between registration (userId present) and binding, only binding is redone without reopening the webview.
    case userBound
    case userRegistered
    // [vcId: issuer endpoint] mapping for VCs issued in proxy mode — kept so revocation can look up by vcId
    // which issuer host to send that VC to.
    case issuerEndpoints
    // The two issuer tables for revoking OID4VCI credentials (`OID4VcIssuerStore`) — canonical issuer [issuerKey: credential_issuer]
    // and the [credential id: issuerKey] reference. They are in allCases, so app reset wipes them too.
    case oid4vcIssuers
    case oid4vcCredentialIssuers
    // User-configured addresses saved on the Server URL screen (`ServerURLStore`). They are in allCases, so
    // app reset wipes them too and the build defaults come back.
    case serverURLs
    // Settings · Proximity · BLE Transfer Mode (`BleTransferMode`). It is in allCases, so
    // app reset wipes it too and it returns to the default Both.
    case bleTransferMode
}

/// BLE role the wallet takes in proximity presentation. Sheet order = this order (Both is the default and recommended).
///
/// The value is passed to the communication SDK's `MdocDeviceConfiguration.bleAdvertiseMode` to narrow the set of modes
/// put into device engagement — Both advertises both modes and the reader picks; a single mode advertises only that one.
nonisolated enum BleTransferMode: String, CaseIterable {
    case both
    case centralClient
    case peripheralServer

    static let `default`: BleTransferMode = .both

    var label: String {
        switch self {
        case .both:             "Both"
        case .centralClient:    "Central client mode"
        case .peripheralServer: "Peripheral server mode"
        }
    }
}

nonisolated enum Preference {

    private static let defaults = UserDefaults.standard

    static func getUserId() -> String? {
        defaults.string(forKey: PreferenceKey.userId.rawValue)
    }

    static func setUserId(_ userId: String) {
        defaults.setValue(userId, forKey: PreferenceKey.userId.rawValue)
    }

    /// Raw username from the registration webview (unprocessed). nil if the server sent an empty value or the wallet predates webview registration.
    static func getUserName() -> String? {
        defaults.string(forKey: PreferenceKey.userName.rawValue)
    }

    static func setUserName(_ userName: String) {
        defaults.setValue(userName, forKey: PreferenceKey.userName.rawValue)
    }

    static func isUserBound() -> Bool {
        defaults.bool(forKey: PreferenceKey.userBound.rawValue)
    }

    static func setUserBound(_ value: Bool) {
        defaults.setValue(value, forKey: PreferenceKey.userBound.rawValue)
    }

    /// Looks up the issuer endpoint of a proxy-issued VC (for revocation routing). nil for direct (TAS) issuance.
    static func getIssuerEndpoint(forVcId vcId: String) -> String? {
        let map = defaults.dictionary(forKey: PreferenceKey.issuerEndpoints.rawValue) as? [String: String]
        return map?[vcId]
    }

    /// Adds one entry to the [vcId: endpoint] mapping right after proxy issuance.
    static func setIssuerEndpoint(_ endpoint: String, forVcId vcId: String) {
        var map = (defaults.dictionary(forKey: PreferenceKey.issuerEndpoints.rawValue) as? [String: String]) ?? [:]
        map[vcId] = endpoint
        defaults.setValue(map, forKey: PreferenceKey.issuerEndpoints.rawValue)
    }

    /// Removes the VC from the [vcId: endpoint] mapping after revocation completes.
    static func removeIssuerEndpoint(forVcId vcId: String) {
        guard var map = defaults.dictionary(forKey: PreferenceKey.issuerEndpoints.rawValue) as? [String: String] else {
            return
        }
        map.removeValue(forKey: vcId)
        defaults.setValue(map, forKey: PreferenceKey.issuerEndpoints.rawValue)
    }

    /// Defaults to Both when nothing is stored or the value is unknown.
    static var bleTransferMode: BleTransferMode {
        get {
            defaults.string(forKey: PreferenceKey.bleTransferMode.rawValue)
                .flatMap(BleTransferMode.init(rawValue:)) ?? .default
        }
        set { defaults.setValue(newValue.rawValue, forKey: PreferenceKey.bleTransferMode.rawValue) }
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
