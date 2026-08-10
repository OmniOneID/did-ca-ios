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

struct ProximityView: View {
    var onBack: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image(.icBack)
                        .padding()
                }
                Spacer()
            }
            .frame(height: 56)
            .background(Color.backgroundGray.ignoresSafeArea(edges: .top))

            VStack(alignment: .leading, spacing: 6) {
                Text("Present certificate in person")
                    .font(.pretendard(size: 22, weight: .bold))
                    .foregroundStyle(.black)
                Text("Show this QR code to the Relying Party to present your digital certificate.")
                    .font(.pretendard(size: 13, weight: .regular))
                    .foregroundStyle(.customGray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)

            Spacer()
            FakeQRView(size: 240)
            Spacer()

            VStack(spacing: 16) {
                Text("Or share via NFC")
                    .font(.pretendard(size: 12, weight: .semibold))
                    .foregroundStyle(.customGray)
                    .kerning(0.5)

                Image(.icNfcBadge)
                    .frame(width: 56, height: 56)
                    .background(
                        Circle()
                            .fill(.paleOrange)
                    )

                Text("Hold your phone near the reader to scan.")
                    .font(.pretendard(size: 12, weight: .regular))
                    .foregroundStyle(.customGray)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 240)
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .overlay(
                Rectangle().frame(height: 1).foregroundStyle(.borderGray),
                alignment: .top
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.backgroundGray)
    }
}

private struct FakeQRView: View {
    let size: CGFloat

    var body: some View {
        let cells = Self.cells
        return ZStack {
            Canvas { ctx, _ in
                let cell = size / 25
                for (r, c) in cells {
                    let isFinderArea = (r < 8 && c < 8) || (r < 8 && c > 16) || (r > 16 && c < 8)
                    if isFinderArea { continue }
                    let rect = CGRect(
                        x: CGFloat(c) * cell,
                        y: CGFloat(r) * cell,
                        width: cell, height: cell
                    )
                    ctx.fill(Path(rect), with: .color(.black))
                }
            }
            .frame(width: size, height: size)

            VStack {
                HStack {
                    Finder(cell: size / 25)
                    Spacer()
                    Finder(cell: size / 25)
                }
                Spacer()
                HStack {
                    Finder(cell: size / 25)
                    Spacer()
                }
            }
            .frame(width: size, height: size)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white)
                .stroke(.borderGray, lineWidth: 1)
        )
    }

    private static let cells: [(Int, Int)] = {
        var out: [(Int, Int)] = []
        for r in 0..<25 {
            for c in 0..<25 {
                let v = sin(Double(r) * 7.3 + Double(c) * 3.1) + cos(Double(r) * 1.7 + Double(c) * 5.9)
                if v > 0.2 { out.append((r, c)) }
            }
        }
        return out
    }()
}

private struct Finder: View {
    let cell: CGFloat
    var body: some View {
        ZStack {
            Rectangle().fill(.black).frame(width: cell * 7, height: cell * 7)
            Rectangle().fill(.white).frame(width: cell * 5, height: cell * 5)
            Rectangle().fill(.black).frame(width: cell * 3, height: cell * 3)
        }
    }
}

#Preview {
    ProximityView()
}
