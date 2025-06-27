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

@IBDesignable
class UnderlinedTextField: UITextField {

    // 선 색상 변경 가능하도록 설정
    @IBInspectable var underlineColor: UIColor = .black {
        didSet {
            setNeedsDisplay()
        }
    }

    private var underlineLayer: CALayer?

    override func layoutSubviews() {
        super.layoutSubviews()

        // 이전 선 제거
        underlineLayer?.removeFromSuperlayer()

        // 새로운 선 추가
        let underline = CALayer()
        underline.backgroundColor = underlineColor.cgColor
        underline.frame = CGRect(x: 0, y: frame.height - 1, width: frame.width, height: 1)

        layer.addSublayer(underline)
        underlineLayer = underline
    }
}
