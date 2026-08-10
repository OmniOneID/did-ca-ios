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

struct OverlayContainerView: View {
    @State private var manager = OverlayManager.shared
    
    var body: some View {
        ZStack(alignment: .top) {
            // Popup Layer
            if let popup = manager.currentPopup {
                PopupView(popup: popup) {
                    manager.dismissPopup()
                }
                .zIndex(2) // Above app content, below loading
            }
            
            // Toast Layer
            VStack(spacing: 8) {
                Spacer() // Push toasts to bottom
                ForEach(manager.activeToasts) { toast in
                    ToastView(toast: toast)
//                    {
//                        manager.dismissToast(id: toast.id)
//                    }
                }
            }
            .padding(.bottom, 50) // Safe area buffer from bottom
            .zIndex(3) // Above popups
            .allowsHitTesting(!manager.activeToasts.isEmpty) // Pass touches if empty
            
            // Loading Layer
            if manager.isLoading {
                LoadingView()
                    .zIndex(4) // Top most blocking layer
            }
        }
        .animation(.spring(), value: manager.activeToasts)
        .animation(.easeOut(duration: 0.24), value: manager.currentPopup)
        .animation(.easeInOut, value: manager.isLoading)
    }
}

#Preview {
    OverlayContainerView()
}
