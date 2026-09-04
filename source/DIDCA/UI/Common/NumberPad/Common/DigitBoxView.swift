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

struct DigitBoxView: View {
    /// true 면 채워진 칸을 점으로 가린다(PIN). false 면 입력한 숫자를 그대로 보여 준다(TX Code).
    var maskDigits: Bool = false
    @Binding var digits: String
    var maxDigits: Int = 6

    var isErrored: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<maxDigits, id: \.self) { index in
                let isFilled = index < digits.count
                let isFocused = index == digits.count
                let digit = isFilled
                    ? String(digits[digits.index(digits.startIndex, offsetBy: index)])
                    : ""

                RoundedRectangle(cornerRadius: 8)
                    .fill((isErrored) ? Color.paleRed : Color.white)
                    .stroke(
                        (isFocused
                         ? Color.customPrimary
                         : (isErrored) ? Color.customRed : Color.dotGray),
                         lineWidth: 1.5)
                    .frame(width: 44, height: 52)
                    .overlay {
                        if isFilled {
                            if maskDigits {
                                Circle()
                                    .fill(isErrored ? Color.customRed : Color.black)
                                    .frame(width: 12, height: 12)
                            } else {
                                Text(digit)
                                    .font(.pretendard(size: 22, weight: .semibold))
                                    .foregroundStyle(isErrored ? Color.customRed : Color.black)
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.15), value: isErrored)
                    .animation(.easeInOut(duration: 0.15), value: digits)
            }
        }
    }
}

#Preview {
    DigitBoxView(maskDigits: false, digits: .constant("454"), maxDigits: 6)
    
}
