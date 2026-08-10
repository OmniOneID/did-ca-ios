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

struct FormatBadge: View {
    let kind: CredentialFormat

    var body: some View {
        Text(kind.rawValue)
            .font(.pretendard(size: 11, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(background)
                    .stroke(foreground.opacity(0.2), lineWidth: 1)
            )
    }

    private var foreground: Color {
        switch kind {
        case .sdJwt: return .badgeSdJwtText
        case .mDoc:  return .badgeMDocText
        case .vc:    return .primaryDark
        case .zkp:   return .badgeZkpText
        }
    }

    private var background: Color {
        switch kind {
        case .sdJwt: return .badgeSdJwt
        case .mDoc:  return .badgeMDoc
        case .vc:    return .paleOrange
        case .zkp:   return .badgeZkp
        }
    }
}

#Preview {
    HStack {
        FormatBadge(kind: .sdJwt)
        FormatBadge(kind: .mDoc)
        FormatBadge(kind: .vc)
        FormatBadge(kind: .zkp)
    }
    .padding()
}
