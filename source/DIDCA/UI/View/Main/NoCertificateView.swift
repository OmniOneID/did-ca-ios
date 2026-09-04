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

struct NoCertificateView : View {

    /// 중앙 아이콘 탭 — 상단 `+` 와 같은 동작(Add certificate 시트)을 호출한다.
    /// 시트 상태는 `MainView` 가 들고 있어 여기서는 클로저로만 받는다.
    var onAdd: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 24) {
            Button(action: onAdd) {
                Circle()
                    .frame(width: 120, height: 120)
                    .foregroundStyle(.white)
                    .shadow(color: .primaryShadow.opacity(0.12), radius: 10, x: 0, y: 6)
                    .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
                    .overlay {
                        Image(.icDocsEmpty)
                            .frame(width: 72, height: 72)
                    }
            }
            .buttonStyle(.plain)
            .contentShape(Circle())

            VStack(alignment: .center, spacing: 8) {
                Text("No Certificates yet")
                    .font(.pretendard(size: 18, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(.black)
                
                HStack(spacing: 4) {
                    Text("Tap the")
                        .font(.pretendard(size: 14, weight: .regular))
                        .foregroundStyle(.customGray)
                    
                    Image(.icAddOrange)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 9, height: 16)

                    
                    Text("icon at the top to add one.")
                        .font(.pretendard(size: 14, weight: .regular))
                        .foregroundStyle(.customGray)
                    
                }
            }
        }
    }
}


#Preview {
    NoCertificateView(onAdd: {})
}
