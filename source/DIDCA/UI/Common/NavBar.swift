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

/// 앱 공통 상단바 — 주황(`customPrimary`) 배경이 상태바까지 덮고, 흰색 타이틀이 가운데 놓인다.
/// 주황 밴드의 총 높이는 `56 + 상태바`다.
///
/// 콘텐츠 높이는 56 뿐이고 `safeAreaPadding(.top)` 을 붙이지 않는다 — 이 바는 NavigationStack /
/// fullScreenCover 안에서 이미 safe area 안쪽에 배치되므로, 거기 또 얹으면 상태바 높이가 두 번
/// 들어가 밴드가 상태바만큼 더 두꺼워진다. 배경만 `ignoresSafeArea` 로 위를 덮으면 된다.
///
/// 좌측 아이콘은 기본이 뒤로(←)이며, 우측은 타이틀을 정중앙에 두기 위한 같은 크기의 빈 자리다.
/// 발급 웹뷰들이 진입 전 화면과 같은 상단을 쓰도록 만든 컴포넌트로, 다른 화면들은 아직 각자
/// 같은 모양을 인라인으로 갖고 있다(공통화는 후속).
struct NavBar: View {

    let title: String
    var icon: ImageResource = .icBackWhite
    let action: () -> Void

    var body: some View {
        HStack {
            Button(action: action) {
                Image(icon).padding()
            }

            Text(title)
                .font(.pretendard(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            Image(icon).padding().hidden()
        }
        .frame(height: 56)
        .background { Color.customPrimary.ignoresSafeArea(edges: .top) }
    }
}

#Preview {
    VStack(spacing: 0) {
        NavBar(title: "Add certificate information") {}
        Spacer()
    }
}
