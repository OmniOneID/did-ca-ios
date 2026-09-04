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
import UIKit

/// 이미지 클레임(portrait 등) 렌더링 — 설계서 VC-B-02 / PRES-B-04. 상세화면과 VP 제시화면이 공유한다.
///
/// - **원본 크기 그대로** 그린다. 확대하지 않는다.
/// - 표시 가능 폭을 넘을 때만 가로세로 비율을 유지한 채 줄인다. 잘라내지 않는다.
/// - **높이 상한은 두지 않는다** — 세로로 긴 이미지는 행 높이가 그만큼 늘어난다.
/// - 좌측 정렬. 라운드 처리나 테두리는 적용하지 않는다.
///
/// 설계서의 px→dp 환산에 대응해 원본 픽셀을 화면 배율로 나눠 pt 로 옮긴다
/// (예: 100×120px, 3x 화면 ≒ 33×40pt). 배율은 `UIScreen` 대신 환경값을 쓴다 —
/// `UIScreen.main` 은 iOS 26 에서 deprecated 다.
struct ClaimImageView: View {
    let data: Data

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        // 값은 매핑 단계(`ImageClaim.decode`)에서 이미 이미지로 열리는지 확인됐다.
        // 그래도 실패하면 아무것도 그리지 않는다 — 오류 다이얼로그는 띄우지 않는다(VC-B-03).
        if let uiImage = UIImage(data: data) {
            let natural = naturalSize(of: uiImage)
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                // 상한이 원본 크기라 확대는 일어나지 않고, 폭이 좁으면 비율을 유지한 채 줄어든다.
                .frame(maxWidth: natural.width, maxHeight: natural.height)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 원본 픽셀 크기 ÷ 화면 배율 = pt 크기.
    /// `UIImage(data:)` 의 scale 은 1 이라 `size` 가 곧 픽셀이지만, 그 전제를 코드에 박지 않는다.
    private func naturalSize(of image: UIImage) -> CGSize {
        let pixels = CGSize(width: image.size.width * image.scale,
                            height: image.size.height * image.scale)
        let scale = displayScale > 0 ? displayScale : 1
        return CGSize(width: pixels.width / scale, height: pixels.height / scale)
    }
}
