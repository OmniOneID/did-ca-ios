//
/*
 * Copyright 2025 OmniOne.
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

class RoundedLabel: UILabel {

    static let defaultRadius: CGFloat = 10
    
    @IBInspectable var cornerRadius: CGFloat = defaultRadius {
        didSet {
            layer.cornerRadius = cornerRadius
            layer.masksToBounds = true
        }}
    
    @IBInspectable var borderWidth : CGFloat = 0 {
        didSet {
            layer.borderWidth = borderWidth
            layer.masksToBounds = true
        }
    }
    
    @IBInspectable var borderColor : UIColor = ColorPalette.primary {
        didSet {
            layer.borderColor = borderColor.cgColor
            layer.masksToBounds = true
        }
    }

}
