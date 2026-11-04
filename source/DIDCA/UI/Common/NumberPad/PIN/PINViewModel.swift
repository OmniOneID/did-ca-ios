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

// Local error to signal a failed authentication when authenticateLock returns nil (doesn't throw) for a wrong passcode.
// The catch side only shows a message, so no payload is needed — the case existing is enough to create a throw path.
private enum PINAuthError: Error {
    case incorrectPasscode
}

enum PINMode {
    case create(isChanging:Bool = false, isLockAuth: Bool = false)
    case confirm(isChanging:Bool = false, isLockAuth: Bool = false)
    case auth(isLockAuth: Bool = false)
    case change(isLockAuth: Bool = false)

    // Whether this is a lock (Unlock) context. Each case carries it directly so it survives the create→confirm and
    // change→create transitions (single source for splitting wording and errors into normal/Unlock).
    var isLockAuth: Bool {
        switch self {
        case .create(_, let lock), .confirm(_, let lock), .auth(let lock), .change(let lock):
            return lock
        }
    }

    // Design spec ScrPin: "PIN" for normal, "Unlock PIN" for lock.
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
            // On successful .change auth → moving to .create, don't leave the red marking from the previous wrong entry.
            clearError()
        }
    }
    // Input-complete signal. A token that gets a new value each time, not a Bool latch — the caller sometimes receives
    // completion yet doesn't close the screen (completePinChange shows only an error popup and keeps the modal if
    // changePin/changeLock fails); with a Bool the second completion wouldn't change the value, so
    // onChange wouldn't fire. The pad would then accept input with no response at all.
    var completionToken: UUID?
    
    // The error message and the error state itself — the view draws even the red marking (DigitBoxView.isErrored) from this.
    // Shown for 1 second, then the message and input are cleared together and input is taken again at the same step.
    // While shown, all keypad input (digits · delete) is ignored (same rule for every PIN and Unlock PIN register/auth/change error).
    var errorMessage : String?

    private static let errorDisplay: Duration = .seconds(1)
    private var errorResetTask: Task<Void, Never>?

    // Whether this PIN screen is an Unlock (lock) context — immutable for the instance's lifetime, so captured once in init.
    // Used to split the error message into normal ("Wrong PIN.") vs unlock ("Wrong unlock PIN.").
    // (The register/confirm mismatch message is the same regardless of lock, so .create/.confirm are false.)
    private let lockContext: Bool

    let maxDigits = 6


    init(mode: PINMode = .create()) {
        self.mode = mode
        lockContext = mode.isLockAuth
    }
    
    func addDigit(_ digit: String) {
        // Key input isn't accepted while an error is shown — it clears itself after 1 second.
        guard errorMessage == nil else { return }
        guard tempPIN.count < maxDigits else { return }

        withAnimation {
            tempPIN.append(digit)
        }
        
        if tempPIN.count == maxDigits {
            // Small delay for better UX
            Task {
                try? await Task.sleep(for: .milliseconds(200))
                await self.verifyPin()
            }
        }
    }
    
    func deleteDigit() {
        guard errorMessage == nil, !tempPIN.isEmpty else { return }
        _ = withAnimation {
            tempPIN.removeLast()
        }
    }

    func deleteAllDigits() {
        guard errorMessage == nil, !tempPIN.isEmpty else { return }
        withAnimation {
            tempPIN.removeAll()
        }
    }
    
    private func verifyPin() async {
        switch mode {
        case .create(let isChanging, _):
            // Change: new PIN is identical to the existing one.
            if isChanging, tempPIN == currentPIN {
                triggerError(message: lockContext
                    ? "New Unlock PIN must be different."
                    : "New PIN must be different.")
                return
            }
            newPIN = tempPIN
            mode = .confirm(isChanging: isChanging, isLockAuth: lockContext)
        case .confirm:
            // Register/change: re-entry mismatch. Stay on the Re-enter step and keep the previous step's PIN (newPIN).
            // The message is the same in the Unlock context.
            if newPIN == tempPIN { completionToken = UUID() }
            else { triggerError(message: "PINs do not match.") }
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
                // Wrong entry on authentication.
                triggerError(message: lockContext ? "Wrong unlock PIN." : "Wrong PIN.")
            }
        case .change(let isLockAuth):
            let pin = tempPIN
            do
            {
                // Re-authenticating the current PIN in the change flow: call authenticateLock(isChanging:) with true so it only
                // checks the old passcode and doesn't touch the global lock state.
                try await Self.runPinAuth(isLockAuth: isLockAuth, pin: pin, isChanging: true)
                currentPIN = pin
                mode = .create(isChanging: true, isLockAuth: isLockAuth)
            }
            catch
            {
                // Change: current PIN authentication failed.
                triggerError(message: lockContext ? "Wrong unlock PIN." : "Wrong PIN.")
            }
        }
    }

    // Runs the synchronous SDK auth call off the MainActor (global executor) — prevents blocking the PIN input UI.
    // Note: authenticateLock doesn't throw on a wrong passcode; it returns nil (SDK contract:
    // "authenticated data if correct, otherwise nil"). Unlike authenticatePin (throws), the return value must be
    // checked directly and nil must throw to catch a failed auth — otherwise the lock passes straight through.
    nonisolated private static func runPinAuth(isLockAuth: Bool, pin: String, isChanging: Bool = false) async throws {
        if isLockAuth {
            guard try WalletAPI.shared.authenticateLock(passcode: pin, isChanging: isChanging) != nil else {
                throw PINAuthError.incorrectPasscode
            }
        } else {
            try WalletAPI.shared.authenticatePin(id: KeyIdName.pin, pin: pin)
        }
    }
    
    // Entry point for showing an error. Clears the message and input together after 1 second.
    private func triggerError(message: String) {
        errorMessage = message
        errorResetTask?.cancel()
        errorResetTask = Task {
            try? await Task.sleep(for: Self.errorDisplay)
            guard !Task.isCancelled else { return }
            withAnimation {
                tempPIN = ""
                errorMessage = nil
            }
        }
    }

    // Clear error — when the step changes, removes the previous error marking and the scheduled reset together.
    private func clearError() {
        errorResetTask?.cancel()
        errorResetTask = nil
        guard errorMessage != nil else { return }
        withAnimation { errorMessage = nil }
    }
}

