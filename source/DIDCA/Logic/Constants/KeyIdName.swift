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

// Immutable key identifier constants — value type String, so safe to read from any actor.
// Lets them be referenced without warnings from nonisolated issuance/auth paths outside the default MainActor
// isolation (SWIFT_DEFAULT_ACTOR_ISOLATION) (BiometricError, UpdateUserProtocol, PINViewModel).
nonisolated struct KeyIdName {
    static let pin:      String = "pin"
    static let bio:      String = "bio"
    static let keyAgree: String = "keyagree"
}
