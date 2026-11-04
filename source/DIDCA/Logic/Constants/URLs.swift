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

/// The 6 server addresses — in the same order as the Endpoints card on the Settings · Server URL screen.
///
/// `defaultValue` is **the build default and an immutable constant**. User settings (`ServerURLStore`) don't erase
/// this value but layer on top of it, and resetting to Default always returns here.
nonisolated enum ServerEndpoint: String, CaseIterable, Sendable {
    case tas
    case cas
    case apiGateway
    case wallet
    case verifier
    case demo

    var label: String {
        switch self {
        case .tas:        "TAS"
        case .cas:        "CAS"
        case .apiGateway: "API Gateway"
        case .wallet:     "Wallet"
        case .verifier:   "Verifier"
        case .demo:       "Demo"
        }
    }

    var defaultValue: String {
        switch self {
        case .tas:        "http://192.168.3.110:8090"
        case .cas:        "http://192.168.3.110:8094"
        case .apiGateway: "http://192.168.3.110:8093"
        case .wallet:     "http://192.168.3.110:8095"
        case .verifier:   "http://192.168.3.110:8092"
        case .demo:       "http://192.168.3.110:8099"
        }
    }
}

/// The address used by networking callers. If the user saved a Custom value on the Server URL screen, it's that value;
/// otherwise `ServerEndpoint.defaultValue` (the build default).
///
/// Reads the store every time — so a saved address takes effect from the very next request. Callers must
/// not store this value in a `static let`; read it every time a request is built.
nonisolated enum URLs {
    static var TAS_URL      : String { ServerURLStore.value(.tas) }
    static var VERIFIER_URL : String { ServerURLStore.value(.verifier) }
    static var CAS_URL      : String { ServerURLStore.value(.cas) }
    static var WALLET_URL   : String { ServerURLStore.value(.wallet) }
    static var API_URL      : String { ServerURLStore.value(.apiGateway) }
    static var DEMO_URL     : String { ServerURLStore.value(.demo) }
}
