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

class PassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        
        // Check if we have any blocking overlays (Popup or Loading)
        // If so, we should consume all touches (do not pass through)
        if OverlayManager.shared.currentPopup != nil || OverlayManager.shared.isLoading
        {
            return hitView
        }
        
        // For non-blocking overlays (like simple Toasts), we want to pass through
        // touches that land on the empty transparent background.
        if hitView == rootViewController?.view {
            return nil
        }
        
        return hitView
    }
}
