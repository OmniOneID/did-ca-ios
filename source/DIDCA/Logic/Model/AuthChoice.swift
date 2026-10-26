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

// Represents which authentication method the user signs with, e.g. in the issuance flow.
//   .pin(_) : PIN authentication done — carries the entered passcode
//   .bio    : biometric authentication chosen — no passcode. When the SDK calls getSignedDidAuth(passcode: nil)
//             and uses the bio key, iOS shows the FaceID/TouchID prompt automatically.
enum AuthChoice {
    case pin(String)
    case bio

    var passcode: String? {
        if case .pin(let p) = self { return p }
        return nil
    }
}

// Intermediate type used only when the selection sheet returns the user's pick as its result.
// Inside presentAuth this pick is chained into the PIN modal or mapped straight to .bio.
enum AuthSelectionPick {
    case pin
    case bio
}
