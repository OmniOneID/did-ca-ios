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

struct StatusBadge: View {
    let status: CredentialStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(foreground)
                .frame(width: 6, height: 6)

            Text(status.rawValue)
                .font(.pretendard(size: 11, weight: .semibold))
                .foregroundStyle(foreground)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(background)
        )
    }

    private var foreground: Color {
        switch status {
        case .active:   return .statusActiveText
        case .inactive: return .customGray
        case .expired:  return .customRed
        }
    }

    private var background: Color {
        switch status {
        case .active:   return .statusActive
        case .inactive: return .statusInactive
        case .expired:  return .statusExpired
        }
    }
}

#Preview {
    HStack {
        StatusBadge(status: .active)
        StatusBadge(status: .inactive)
        StatusBadge(status: .expired)
    }
    .padding()
}
