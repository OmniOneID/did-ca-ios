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
        secondaryAction: (() -> Void)? = nil
    ) {
        let primary = Popup.PopupButton(title: primaryButtonTitle, action: primaryAction)
        let secondary = secondaryButtonTitle.map {
            Popup.PopupButton(title: $0, action: secondaryAction ?? {})
        }
        hideLoading()
        
        withAnimation(.spring(duration: 0.3)) {
            self.currentPopup = Popup(
                title: title,
                message: message,
                primaryButton: primary,
                secondaryButton: secondary
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

        // 로딩을 내리지 않는다 — 토스트는 흐름을 끝내지 않는 알림이라, 배경에서 뜬 토스트가
        // (예: loadCredentials 중 SD-JWT 상태 조회 실패) 진행 중인 발급·폐기의 스피너를
        // 걷어내면 안 된다. HUD 는 터치를 막지 않는 PassThroughWindow 라 스피너가 사라진
        // 화면은 그대로 조작 가능해져 같은 동작이 두 번 시작될 수 있다.
        // (showPopup 의 hideLoading 은 유지 — 에러 팝업은 흐름을 끝내는 게 맞다.)

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
    /// - parameter animated: false 면 페이드 없이 즉시 표시. 인증 모달 dismiss 와 같은
    ///   프레임에 opaque 로 띄워, 슬라이드다운 중 맨 화면이 비치는 갭을 없앨 때 쓴다.
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
            // 뷰단 `.animation(value: isLoading)` 까지 이 트랜잭션이 억제 → 페이드 없이 즉시.
            var txn = Transaction()
            txn.disablesAnimations = true
            withTransaction(txn) {
                isLoading = shoudShow
            }
        }
    }
}

