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

/// VC 상세화면 상단 히어로 — 컬러 배경 + 타이틀 + 발급정보 카드.
/// 백/휴지통 네비바는 `VCDetailView` 가 고정 영역으로 따로 그리며,
/// 이 히어로는 그 네비바 아래 스크롤 영역의 첫 콘텐츠로 들어간다.
struct CredentialHero: View {
    let credential: Credential
    /// 상세화면 진입 시 새로 조회한 상태로 뱃지를 덮어쓴다. nil 이면 credential.status 사용.
    var statusOverride: CredentialStatus? = nil

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                Color.customPrimary

                VStack(alignment: .leading, spacing: 4) {
                    Text("CERTIFICATE")
                        .font(.pretendard(size: 12, weight: .semibold))
                        .kerning(1)
                        .foregroundStyle(.white.opacity(0.85))

                    Text(credential.name)
                        .font(.pretendard(size: 22, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 96)
            }

            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image(.icIdLarge)
                        .frame(width: 56, height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(
                                    LinearGradient(
                                        colors: [.paleOrange, .borderOrange],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Issued by")
                            .font(.pretendard(size: 12, weight: .medium))
                            .foregroundStyle(.customGray)

                        Text(credential.issuer)
                            .font(.pretendard(size: 14, weight: .bold))
                            .foregroundStyle(.black)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 6) {
                    StatusBadge(status: statusOverride ?? credential.status)
                    FormatBadge(kind: credential.badge)
                    if credential.zkp { FormatBadge(kind: .zkp) }
                    Spacer()
                }

                DashLiner()
                    .stroke(.borderGray, style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .frame(height: 1)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ISSUED")
                            .font(.pretendard(size: 10, weight: .semibold))
                            .kerning(0.4)
                            .foregroundStyle(.customGray)
                        Text(credential.issued ?? "—")
                            .font(.pretendard(size: 13, weight: .semibold))
                            .foregroundStyle(.black)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("VALID UNTIL")
                            .font(.pretendard(size: 10, weight: .semibold))
                            .kerning(0.4)
                            .foregroundStyle(.customGray)
                        Text(credential.valid ?? "—")
                            .font(.pretendard(size: 13, weight: .semibold))
                            .foregroundStyle(.black)
                    }
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.white)
                    .shadow(color: .primaryShadow.opacity(0.08), radius: 6, x: 0, y: 4)
                    .shadow(color: .black.opacity(0.03), radius: 1, x: 0, y: 1)
            )
            .padding(.horizontal, 16)
            .offset(y: -72)
            .padding(.bottom, -72)
        }
    }
}

#Preview {
    ScrollView {
        CredentialHero(credential: SampleCredentials.mdl)
    }
}
