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

@Observable
final class OverlayManager {
    // Singleton for easy access (optional, can be injected via Environment)
    static let shared = OverlayManager()
    
    // MARK: - State
    
    // Popups
    var currentPopup: Popup?
    
    // Toasts
    var activeToasts: [Toast] = []
    
    // Loading
    var isLoading: Bool = false
//    private var loadingCount: Int = 0
    
    // MARK: - Public Methods
    
    // Popup
    @MainActor
    func showPopup(
        title: String,
        message: String,
        primaryButtonTitle: String = "OK",
        primaryAction: @escaping () -> Void = {},
        secondaryButtonTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil,
        linkButtonTitle: String? = nil,
        linkAction: (() -> Void)? = nil
    ) {
        let primary = Popup.PopupButton(title: primaryButtonTitle, action: primaryAction)
        let secondary = secondaryButtonTitle.map {
            Popup.PopupButton(title: $0, action: secondaryAction ?? {})
        }
        // Text link below the buttons. No action means no link (avoids a link with nothing to tap).
        let link = linkButtonTitle.flatMap { title in
            linkAction.map { Popup.PopupButton(title: title, action: $0) }
        }
        hideLoading()
        
        withAnimation(.spring(duration: 0.3)) {
            self.currentPopup = Popup(
                title: title,
                message: message,
                primaryButton: primary,
                secondaryButton: secondary,
                linkButton: link
            )
        }
    }
    
    @MainActor
    func dismissPopup() {
        withAnimation(.easeOut(duration: 0.2)) {
            self.currentPopup = nil
        }
    }
    
    // Toast
    @MainActor
    func showToast(message: String, duration: TimeInterval = 2.0) {
        let toast = Toast(message: message, duration: duration)

        // Doesn't dismiss loading — a toast is a notification that doesn't end the flow, so a toast raised in the background
        // (e.g. SD-JWT status lookup failure during loadCredentials) must not remove the spinner of an in-progress
        // issuance/revocation. The HUD is a PassThroughWindow that doesn't block touches, so a screen whose spinner
        // disappeared becomes operable again and the same action could start twice.
        // (showPopup's hideLoading stays — an error popup should end the flow.)

        withAnimation(.snappy) {
            activeToasts.append(toast)
        }
        
        // Auto-dismiss
        Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            dismissToast(id: toast.id)
        }
    }
    
    @MainActor
    func dismissToast(id: UUID) {
        withAnimation(.easeOut(duration: 0.2)) {
            if let index = activeToasts.firstIndex(where: { $0.id == id }) {
                activeToasts.remove(at: index)
            }
        }
    }
    
    // Loading
    /// - parameter animated: if false, shown immediately without a fade. Used to show it opaque in the same frame as
    ///   the auth modal dismiss, removing the gap where the bare screen shows through during the slide-down.
    @MainActor
    func showLoading(animated: Bool = true) {
//        loadingCount += 1
        updateLoadingState(shoudShow: true, animated: animated)
    }

    @MainActor
    func hideLoading() {
//        loadingCount = max(0, loadingCount - 1)
        updateLoadingState(shoudShow: false)
    }

    private func updateLoadingState(shoudShow : Bool, animated: Bool = true) {
//        let shouldShow = loadingCount > 0
        guard isLoading != shoudShow else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                isLoading = shoudShow
            }
        } else {
            // This transaction suppresses even the view-level `.animation(value: isLoading)` → shown immediately without a fade.
            var txn = Transaction()
            txn.disablesAnimations = true
            withTransaction(txn) {
                isLoading = shoudShow
            }
        }
    }
}

