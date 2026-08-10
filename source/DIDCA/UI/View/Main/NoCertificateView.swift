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
    var body: some View {
        VStack(alignment: .center, spacing: 24) {
            Circle()
                .frame(width: 120, height: 120)
                .foregroundStyle(.white)
                .shadow(color: .primaryShadow.opacity(0.12), radius: 10, x: 0, y: 6)
                .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
                .overlay {
                    Image(.icDocsEmpty)
                        .frame(width: 72, height: 72)
                }

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
    NoCertificateView()
}
