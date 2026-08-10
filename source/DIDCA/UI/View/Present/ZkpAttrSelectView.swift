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

/// ZKP attribute 값 선택 화면 — VPRequestZkpView 의 attribute 행에서 "Tap to select >"
/// 를 누르면 진입. 주어진 referent key 에 대한 후보 raw 값 리스트(`availableValues`)를
/// 표시하고 사용자가 하나를 고르면 `onSelect(index:)` 콜백으로 결과를 반환.
///
/// 후보 값은 사전에 preProcess 단계에서 `searchZKPCredentials` 로 캐시된 sub-referent
/// 들의 raw 문자열. 인덱스가 그대로 `UserReferent(attrReferent:selectedIndex:...)` 에
/// 전달돼 SDK 에서 사용된다.
struct ZkpAttrSelectView: View {
    let label: String
    let availableValues: [ZkpAvailableValue]
    /// 외부(coordinator) 가 단일 소스. @State 로 두면 SwiftUI 가 view identity 유지 시 이전
    /// 화면의 선택값이 남거나 초기화 안 됨 — let 으로 받아 매 진입마다 깨끗한 값으로 표시.
    let selectedIndex: Int?
    var onBack: () -> Void = {}
    var onSelect: (_ index: Int) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image(.icBack)
                        .renderingMode(.template)
                        .foregroundStyle(.white)
                        .padding()
                }
                Text(label)
                    .font(.pretendard(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                Image(.icBack)
                    .padding()
                    .hidden()
            }
            .frame(height: 56)
            .background(Color.customPrimary.ignoresSafeArea(edges: .top))

            if availableValues.isEmpty {
                Text("No matching credential found.")
                    .font(.pretendard(size: 14, weight: .regular))
                    .foregroundStyle(.customGray)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
                Spacer()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(availableValues.enumerated()), id: \.offset) { idx, item in
                        Button {
                            onSelect(idx)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.schemaName)
                                        .font(.pretendard(size: 15, weight: .semibold))
                                        .foregroundStyle(.black)
                                    Text(item.raw)
                                        .font(.pretendard(size: 13, weight: .regular))
                                        .foregroundStyle(.customGray)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                if selectedIndex == idx {
                                    Image(.icCheckOrange)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
                            .background(selectedIndex == idx ? Color.paleOrange : .white)
                        }
                        .buttonStyle(.plain)

                        if idx < availableValues.count - 1 {
                            Rectangle()
                                .fill(.borderGray)
                                .frame(height: 1)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.borderGray, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()
            }
        }
        .background(.backgroundGray)
    }
}

#Preview {
    ZkpAttrSelectView(
        label: "Region",
        availableValues: [
            .init(raw: "Seoul", schemaName: "Driver License"),
            .init(raw: "Seoul", schemaName: "ID Card"),
            .init(raw: "Busan", schemaName: "Driver License")
        ],
        selectedIndex: nil
    )
}
