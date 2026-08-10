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
    

import UIKit
import SwiftUI

class OverlayWindowController: UIViewController {
    
    private var overlayWindow: PassThroughWindow?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupOverlayWindow()
    }
    
    private func setupOverlayWindow() {
        // Create a new window instance
        // In a real app, you might want to attach this to the current UIWindowScene
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        
        let window = PassThroughWindow(windowScene: windowScene)
        window.windowLevel = .alert + 1 // Ensure it is above alerts and other windows
        window.backgroundColor = .clear
        
        // Host the SwiftUI View
        let rootView = OverlayContainerView()
        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = .clear
        
        window.rootViewController = hostingController
        window.isHidden = false
        
        self.overlayWindow = window
    }
}

// Helper to inject into App loop
struct OverlayInjector: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> OverlayWindowController {
        return OverlayWindowController()
    }
    
    func updateUIViewController(_ uiViewController: OverlayWindowController, context: Context) {}
}
