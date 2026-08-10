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

    /// 화면설계서에는 섹션 헤더가 **두 종류**로 정의돼 있다. 화면 계열마다 지정된 쪽을 쓴다 —
    /// 어느 쪽인지는 설계서를 확인하고 임의로 통일하지 않는다.
    enum Style {
        /// 설정 · VC 상세 · VP 요청 (설계서 `sectionTitle()` 헬퍼). 대문자 변환 없음.
        case standard
        /// 발급 목록 계열 — 프로토콜 선택 · Issuer/Credential 목록. 전부 대문자.
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
    /// 지정하지 않으면 스타일 기본값(standard=accentOrange, uppercase=primary).
    var accent: Color? = nil
    /// 스타일의 대소문자 변환만 끈다 — 크기·커닝·막대 색은 스타일 그대로 유지한다.
    /// 고정 문구가 아니라 **서버가 준 값**(Issuer 식별자 등)을 타이틀에 넣을 때 쓴다.
    /// 대문자로 바꾸면 원문이 변형되기 때문이다.
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
