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

struct NumberPadView: View {
    var onDigit: (String) -> Void
    var onDelete: () -> Void
    var onDeleteAll: () -> Void
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(1...9, id: \.self) { number in
                NumberButton(number: "\(number)") {
                    onDigit("\(number)")
                }
            }

            Spacer()

            NumberButton(number: "0") {
                onDigit("0")
            }

            Button(action: onDelete) {
                Image(.icBack)
                    .frame(height: 52)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NumKeyButtonStyle())
        }
        .padding(.top, 8)
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
    }
}


#Preview {
    NumberPadView { num in
        print("num : \(num)")
    } onDelete: {
        ()
    } onDeleteAll: {
        ()
    }
}
