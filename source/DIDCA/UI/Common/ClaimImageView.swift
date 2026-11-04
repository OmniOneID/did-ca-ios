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

/// Image claim (portrait, etc.) rendering. Shared by the detail screen and the VP presentation screen.
///
/// - Drawn **at original size**. Never enlarged.
/// - Shrunk, preserving aspect ratio, only when it exceeds the available width. Never cropped.
/// - **No height cap** — a tall image grows the row height accordingly.
/// - Left-aligned. No rounding or border applied.
///
/// Mirroring the design spec's px→dp conversion, original pixels are divided by the screen scale to get pt
/// (e.g. 100×120px on a 3x screen ≒ 33×40pt). The scale comes from the environment instead of `UIScreen` —
/// `UIScreen.main` is deprecated in iOS 26.
struct ClaimImageView: View {
    let data: Data

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        // The value was already confirmed to open as an image at the mapping stage (`ImageClaim.decode`).
        // If it still fails, nothing is drawn — no error dialog is shown.
        if let uiImage = UIImage(data: data) {
            let natural = naturalSize(of: uiImage)
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                // The cap is the original size so no enlargement happens; if the width is narrow it shrinks preserving the ratio.
                .frame(maxWidth: natural.width, maxHeight: natural.height)
                .accessibilityIdentifier("claimImage")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Original pixel size ÷ screen scale = pt size.
    /// `UIImage(data:)` has scale 1 so `size` is pixels, but that assumption isn't baked into the code.
    private func naturalSize(of image: UIImage) -> CGSize {
        let pixels = CGSize(width: image.size.width * image.scale,
                            height: image.size.height * image.scale)
        let scale = displayScale > 0 ? displayScale : 1
        return CGSize(width: pixels.width / scale, height: pixels.height / scale)
    }
}
