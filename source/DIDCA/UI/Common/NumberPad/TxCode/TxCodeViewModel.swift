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

// OID4VCI Credential Offer 의 pre-authorized_code grant 에 포함된 tx_code 입력 화면(설계서 화면 22, TX Code · Empty).
// 입력이 length 만큼 채워지면 isCompleted 를 올려 별도 Submit 없이 token 요청으로 넘어간다(TXC-B-01).
//
// **이 화면에는 오류 표시가 없다** — TXC-E-01 은 코드가 틀려도 화면을 그냥 닫고, 호출 화면(Certs) 위에
// 다이얼로그를 띄우도록 규정한다. 오류 문구·입력 초기화 상태를 이 뷰모델이 들고 있으면 안 된다.
// 실제 처리는 QRRouter.handleOID4VCI 의 catch (failIssuance fallback "Wrong code.").
@Observable
class TxCodeViewModel {

    // tx_code 객체에서 주입되는 값. 지금은 호출부가 없어 기본값(numeric · 6자리)을 쓴다.
    //  - length: 입력 칸(PinDots) 개수. 설계서: length 값에 맞춰 자동 조절(예: 6 → 6칸, 4 → 4칸).
    //  - codeDescription: tx_code.description 안내 문구.
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

        // TXC-B-01: length 만큼 채워지면 별도 Submit 없이 token 요청 단계로 자동 진행.
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
