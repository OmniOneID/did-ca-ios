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

/// ZKP attribute value selection screen — entered by tapping "Tap to select >" on an attribute row
/// of VPRequestZkpView. Shows the list of candidate raw values (`availableValues`) for the given referent key
/// and returns the result via the `onSelect(index:)` callback when the user picks one.
///
/// Candidate values are the raw strings of sub-referents cached earlier by `searchZKPCredentials`
/// in the preProcess step. The index is passed as-is into `UserReferent(attrReferent:selectedIndex:...)`
/// and used by the SDK.
struct ZkpAttrSelectView: View {
    let label: String
    let availableValues: [ZkpAvailableValue]
    /// The external coordinator is the single source. As @State, SwiftUI keeping view identity could leave the previous
    /// screen's selection or fail to reset — taking it as let shows a clean value on every entry.
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
                .accessibilityIdentifier("backButton")
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
                        .accessibilityIdentifier("optionLabel")
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
