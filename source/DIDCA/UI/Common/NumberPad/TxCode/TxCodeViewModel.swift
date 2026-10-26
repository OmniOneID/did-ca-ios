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
import Observation

// Input screen for the tx_code included in the OID4VCI Credential Offer's pre-authorized_code grant (design spec screen 22, TX Code · Empty).
// Once the input fills up to length, isCompleted is raised and it moves on to the token request without a separate Submit (TXC-B-01).
//
// **This screen has no error display** — TXC-E-01 specifies that even with a wrong code the screen just closes and a dialog
// is shown on top of the calling screen (Certs). This view model must not hold error messages or input-reset state.
// Actual handling is in QRRouter.handleOID4VCI's catch (failIssuance fallback "Wrong code.").
@Observable
class TxCodeViewModel {

    // Values injected from the tx_code object. There's no caller yet, so defaults (numeric · 6 digits) are used.
    //  - length: number of input boxes (PinDots). Design spec: auto-adjusted to the length value (e.g. 6 → 6 boxes, 4 → 4 boxes).
    //  - codeDescription: tx_code.description guidance text.
    let length: Int
    let codeDescription: String

    var code: String = ""
    var isCompleted: Bool = false

    var title: String { "Enter tx code" }
    var message: String {
        codeDescription.isEmpty
            ? "Enter the verification code provided by the issuer."
            : codeDescription
    }

    init(length: Int = 6, description: String = "") {
        self.length = max(1, length)
        self.codeDescription = description
    }

    func addDigit(_ digit: String) {
        guard code.count < length else { return }

        withAnimation {
            code.append(digit)
        }

        // TXC-B-01: once filled up to length, automatically proceed to the token request step without a separate Submit.
        if code.count == length {
            isCompleted = true
        }
    }

    func deleteDigit() {
        guard !code.isEmpty else { return }
        _ = withAnimation {
            code.removeLast()
        }
    }

    func deleteAllDigits() {
        guard !code.isEmpty else { return }
        withAnimation {
            code.removeAll()
        }
    }
}
