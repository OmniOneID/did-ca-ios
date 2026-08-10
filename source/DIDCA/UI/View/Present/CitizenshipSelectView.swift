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

struct CitizenshipOption: Identifiable, Hashable {
    let id: String
    let label: String
    let value: String
}

enum CitizenshipOptions {
    static let all: [CitizenshipOption] = [
        .init(id: "citizen",  label: "ID Card",    value: "citizen"),
        .init(id: "civilian", label: "Passport",   value: "civilian"),
        .init(id: "resident", label: "Membership", value: "resident")
    ]
}

struct CitizenshipSelectView: View {
    @State var selected: String? = "resident"
    var onBack: () -> Void = {}
    var onSelect: (CitizenshipOption) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image(.icBack)
                        .padding()
                }
                Text("Citizenship")
                    .font(.pretendard(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                Image(.icBack)
                    .padding()
                    .hidden()
            }
            .frame(height: 56)
            .background(Color.backgroundGray.ignoresSafeArea(edges: .top))

            VStack(spacing: 0) {
                ForEach(Array(CitizenshipOptions.all.enumerated()), id: \.element.id) { idx, opt in
                    Button {
                        selected = opt.value
                        onSelect(opt)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(opt.label)
                                    .font(.pretendard(size: 15, weight: .semibold))
                                    .foregroundStyle(.black)
                                Text(opt.value)
                                    .font(.pretendard(size: 13, weight: .regular))
                                    .foregroundStyle(.customGray)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if selected == opt.value {
                                Image(.icCheckOrange)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .background(selected == opt.value ? Color.paleOrange : .white)
                    }
                    .buttonStyle(.plain)

                    if idx < CitizenshipOptions.all.count - 1 {
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
        .background(.backgroundGray)
    }
}

#Preview {
    CitizenshipSelectView()
}
