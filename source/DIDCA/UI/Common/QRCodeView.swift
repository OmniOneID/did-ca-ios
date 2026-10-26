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
import CoreImage.CIFilterBuiltins

/// Draws a string as a QR. Generation is a single CoreImage pass, and scaling is done without interpolation
/// (`.interpolation(.none)`) so module edges don't blur — edges are what the scanner reads.
struct QRCodeView: View {
    let content: String
    let size: CGFloat

    var body: some View {
        Group {
            if let image = Self.render(content) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
    }

    private static func render(_ content: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        // The engagement payload isn't short (hundreds of bytes) — lower error correction to keep modules thick.
        filter.correctionLevel = "L"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
