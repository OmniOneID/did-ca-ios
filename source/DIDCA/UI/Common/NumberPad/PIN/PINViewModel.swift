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
import DIDWalletSDK

// authenticateLock 이 틀린 passcode 에 nil 을 반환할 때(throw 안 함) 오인증을 알리기 위한 로컬 에러.
// catch 측은 문구만 보여주므로 내용은 불필요 — case 존재만으로 throw 경로를 만든다.
private enum PINAuthError: Error {
    case incorrectPasscode
}

enum PINMode {
    case create(isChanging:Bool = false, isLockAuth: Bool = false)
    case confirm(isChanging:Bool = false, isLockAuth: Bool = false)
    case auth(isLockAuth: Bool = false)
    case change(isLockAuth: Bool = false)

    // 잠금(Unlock) 맥락 여부. create→confirm, change→create 전환 시에도 보존되도록
    // 각 케이스가 직접 들고 있다 (문구·에러를 일반/Unlock 으로 가르는 단일 소스).
    var isLockAuth: Bool {
        switch self {
        case .create(_, let lock), .confirm(_, let lock), .auth(let lock), .change(let lock):
            return lock
        }
    }

    // 설계서 ScrPin: 일반은 "PIN", 잠금은 "Unlock PIN".
    private var noun: String { isLockAuth ? "Unlock PIN" : "PIN" }

    var title: String {
        switch self {
        case .create(let isChanging, _), .confirm(let isChanging, _):
            return isChanging ? "Change \(noun)" : "Set \(noun)"
        case .auth:
            return "Enter \(noun)"
        case .change:
            return "Change \(noun)"
        }
    }

    var subtitle: String {
        switch self {
        case .create(let isChanging, _):
            return isChanging ? "Type your new \(noun)" : "Type your \(noun)"
        case .confirm(let isChanging, _):
            return isChanging ? "Re-enter the new \(noun)" : "Re-enter your \(noun)"
        case .auth:
            return isLockAuth ? "Type your \(noun) to unlock" : "Type your \(noun) to authenticate"
        case .change:
            return "Type your current \(noun)"
        }
    }
}

@Observable
class PINViewModel {
    var newPIN: String = ""
    var currentPIN: String = ""
    var tempPIN: String = ""
    
    var title : String { mode.title }
    var message : String { mode.subtitle }
    var mode: PINMode = .create()
    {
        didSet {
            tempPIN = ""
            // .change 인증 성공 → .create 로 넘어갈 때 직전 오입력의 붉은 표시가 남지 않게 한다.
            clearError()
        }
    }
    // 입력 완료 신호. Bool 래치가 아니라 매번 새 값을 넣는 토큰이다 — 호출 측이 완료를 받고도
    // 화면을 닫지 않는 경우가 있어서(completePinChange 는 changePin/changeLock 이 실패하면
    // 오류 팝업만 띄우고 모달을 유지한다) Bool 이면 두 번째 완료가 값 변화를 못 만들어
    // onChange 가 울리지 않는다. 그러면 패드가 입력만 받고 아무 반응이 없는 상태가 된다.
    var completionToken: UUID?
    
    // 에러 문구이자 오류 상태 그 자체 — 뷰가 이 값으로 붉은 표시(DigitBoxView.isErrored)까지 그린다.
    // 한번 세워지면 스스로 사라지지 않는다. 유지되는 동안 숫자 키는 받지 않고, 삭제 키만이 해제한다
    // (PIN-A/C-E-01·PIN-C-E-02·PIN-R/C-E-03 과 UNLK 대응 항목 전부 동일 규칙).
    // 입력은 에러 시점에 비우지 않는다 — 스펙의 "입력 초기화 없음".
    var errorMessage : String?

    // 이 PIN 화면이 Unlock(lock) 맥락인지 — 인스턴스 수명 동안 불변이라 init 에서 한 번 캡처.
    // 에러 문구를 normal("Wrong PIN.") vs unlock("Wrong unlock PIN.") 로 가르는 데 쓴다.
    // (register/confirm 불일치 문구는 lock 무관 동일하므로 .create/.confirm 는 false.)
    private let lockContext: Bool

    let maxDigits = 6


    init(mode: PINMode = .create()) {
        self.mode = mode
        lockContext = mode.isLockAuth
    }
    
    func addDigit(_ digit: String) {
        // 에러가 떠 있는 동안은 숫자 키를 받지 않는다 — 해제 수단은 삭제 키뿐이다.
        guard errorMessage == nil else { return }
        guard tempPIN.count < maxDigits else { return }

        withAnimation {
            tempPIN.append(digit)
        }
        
        if tempPIN.count == maxDigits {
            // Small delay for better UX
            Task {
                try await Task.sleep(nanoseconds: 200_000_000)
                await self.verifyPin()
            }
        }
    }
    
    func deleteDigit() {
        // 에러의 유일한 해제 지점. 한 자리씩 지우는 동작은 그대로 두고, 첫 삭제에서
        // 문구와 붉은 표시만 걷어낸다.
        clearError()
        guard !tempPIN.isEmpty else { return }
        _ = withAnimation {
            tempPIN.removeLast()
        }
    }

    func deleteAllDigits() {
        clearError()
        guard !tempPIN.isEmpty else { return }
        withAnimation {
            tempPIN.removeAll()
        }
    }
    
    private func verifyPin() async {
        switch mode {
        case .create(let isChanging, _):
            // PIN-C-E-02 / UNLK-C-E-02: 새 PIN 이 기존과 동일.
            // 설계서는 토스트를 적었지만, 나머지 단계와 동작을 맞추려고 인라인 에러로 바꿨다.
            if isChanging, tempPIN == currentPIN {
                triggerError(message: lockContext
                    ? "New Unlock PIN must be different"
                    : "New PIN must be different")
                return
            }
            newPIN = tempPIN
            mode = .confirm(isChanging: isChanging, isLockAuth: lockContext)
        case .confirm:
            // PIN-R/C-E-03 · UNLK-R/C-E-03: 재입력 불일치.
            // 완료 후에도 입력은 그대로 둔다 — 재시도하려면 사용자가 직접 지워야 하는 것이
            // 화면설계서의 의도다.
            if newPIN == tempPIN { completionToken = UUID() }
            else { triggerError(message: lockContext ? "Unlock PINs do not match" : "PINs do not match") }
        case .auth(let isLockAuth):
            let pin = tempPIN
            do
            {
                try await Self.runPinAuth(isLockAuth: isLockAuth, pin: pin)
                currentPIN = pin
                completionToken = UUID()
            }
            catch
            {
                // PIN-A-E-01 / UNLK-A-E-01: 인증 오입력. 삭제 키를 누를 때까지 유지된다.
                triggerError(message: lockContext ? "Wrong Unlock PIN" : "Wrong PIN")
            }
        case .change(let isLockAuth):
            let pin = tempPIN
            do
            {
                // 변경 플로우의 현재 PIN 재인증: old passcode 확인만 하고 전역 잠금 상태는
                // 건드리지 않도록 authenticateLock(isChanging:) 을 true 로 호출한다.
                try await Self.runPinAuth(isLockAuth: isLockAuth, pin: pin, isChanging: true)
                currentPIN = pin
                mode = .create(isChanging: true, isLockAuth: isLockAuth)
            }
            catch
            {
                // PIN-C-E-01 / UNLK-C-E-01: 현재 PIN 오인증. 삭제 키를 누를 때까지 유지된다.
                triggerError(message: lockContext ? "Wrong Unlock PIN" : "Wrong PIN")
            }
        }
    }

    // 동기 SDK 인증 호출을 MainActor 밖(글로벌 executor)에서 실행 — PIN 입력 UI 블록 방지.
    // 주의: authenticateLock 은 틀린 passcode 에 throw 하지 않고 nil 을 반환한다(SDK 계약:
    // "authenticated data if correct, otherwise nil"). authenticatePin(throw)과 달리 반환값을
    // 직접 검사해 nil 이면 throw 해야 오인증을 잡는다 — 안 하면 잠금이 그대로 통과한다.
    nonisolated private static func runPinAuth(isLockAuth: Bool, pin: String, isChanging: Bool = false) async throws {
        if isLockAuth {
            guard try WalletAPI.shared.authenticateLock(passcode: pin, isChanging: isChanging) != nil else {
                throw PINAuthError.incorrectPasscode
            }
        } else {
            try WalletAPI.shared.authenticatePin(id: KeyIdName.pin, pin: pin)
        }
    }
    
    // 에러 표시 진입점. 입력은 그대로 두고 문구만 세운다 — 해제는 deleteDigit 이 한다.
    private func triggerError(message: String) {
        errorMessage = message
    }

    // 에러 해제 — 문구와 함께 붉은 표시도 걷힌다.
    private func clearError() {
        guard errorMessage != nil else { return }
        withAnimation { errorMessage = nil }
    }
}

