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
// 현재는 화면(UI)만 제공 — 입력이 length 만큼 채워지면 isCompleted 만 올린다.
// token 요청·발급 배선(및 TXC-E-01 "Wrong code." 처리)은 후속 작업: [[project_com02_timeout_followup]] 와 별개로
// 발급 경로가 OID4VCI 를 타게 되는 시점에 onComplete / showError 를 연결한다.
@Observable
class TxCodeViewModel {

    // tx_code 객체에서 주입되는 값. 지금은 호출부가 없어 기본값(numeric · 6자리)을 쓴다.
    //  - length: 입력 칸(PinDots) 개수. 설계서: length 값에 맞춰 자동 조절(예: 6 → 6칸, 4 → 4칸).
    //  - codeDescription: tx_code.description 안내 문구.
    let length: Int
    let codeDescription: String

    var code: String = ""
    var isCompleted: Bool = false
    var errorMessage: String?

    // 에러 후 입력을 유지하되(PIN 화면과 동일 정책), 다음 키 입력 시 새 시도로 보고 비우기 위한 플래그.
    private var resetOnNextInput = false

    var title: String { "Enter code" }
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
        if resetOnNextInput {
            resetOnNextInput = false
            errorMessage = nil
            code = ""
        }
        guard code.count < length else { return }

        withAnimation {
            code.append(digit)
        }

        // 설계서: length 만큼 채워지면 별도 Submit 없이 자동 진행. (token 요청 배선은 후속)
        if code.count == length {
            isCompleted = true
        }
    }

    func deleteDigit() {
        resetOnNextInput = false
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

    // TXC-E-01 대비 — token 요청이 invalid_grant 로 실패하면 "Wrong code." 등을 표시.
    // 발급 배선이 들어오는 후속 작업에서 호출. 입력은 유지하고 다음 키 입력 때 새로 시작한다.
    func showError(_ message: String) {
        resetOnNextInput = true
        errorMessage = message
    }
}
