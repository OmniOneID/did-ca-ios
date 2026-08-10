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

struct NumberButton: View {
    let number: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(number)
                .font(.pretendard(size: 22, weight: .medium))
                .frame(height: 52)
                .frame(maxWidth: .infinity)
                .foregroundStyle(.black)
        }
        .buttonStyle(NumKeyButtonStyle())
    }
}

/// NumberPad 키 공통 스타일 — 화면설계서 NumKey 매핑.
/// pressed 시 배경 paleOrange (C.primaryPale), 120ms ease transition, subtle shadow.
struct NumKeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.paleOrange : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    NumberButton(number: "0") {
        ()
    }
}

