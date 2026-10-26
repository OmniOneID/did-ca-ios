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

struct SectionHeader: View {

    /// The screen design spec defines **two kinds** of section headers. Use the one specified for each screen family —
    /// check the design spec for which one, and don't unify them arbitrarily.
    enum Style {
        /// Settings · VC detail · VP request (design spec `sectionTitle()` helper). No uppercasing.
        case standard
        /// Issuance list family — protocol selection · Issuer/Credential lists. All uppercase.
        case uppercase

        var size: CGFloat {
            switch self {
            case .standard: 13
            case .uppercase: 11
            }
        }

        var kerning: CGFloat {
            switch self {
            case .standard: -0.1
            case .uppercase: 0.3
            }
        }

        var textCase: Text.Case? {
            switch self {
            case .standard: nil
            case .uppercase: .uppercase
            }
        }

        var defaultAccent: Color {
            switch self {
            case .standard: .accentOrange
            case .uppercase: .customPrimary
            }
        }
    }

    let title: String
    var style: Style = .standard
    /// If unspecified, the style default (standard=accentOrange, uppercase=primary).
    var accent: Color? = nil
    /// Turns off only the style's case conversion — size, kerning and bar color stay as the style defines.
    /// Used when putting a **server-provided value** (Issuer identifier, etc.) in the title rather than fixed text,
    /// because uppercasing would alter the original.
    var preservesCase: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent ?? style.defaultAccent)
                .frame(width: 4, height: 16)

            Text(title)
                .font(.pretendard(size: style.size, weight: .bold))
                .kerning(style.kerning)
                .textCase(preservesCase ? nil : style.textCase)
                .foregroundStyle(.black)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }
}

#Preview {
    VStack(alignment: .leading) {
        SectionHeader(title: "Certificate Details")
        SectionHeader(title: "Select Issuance Protocol", style: .uppercase)
    }
    .padding()
}
