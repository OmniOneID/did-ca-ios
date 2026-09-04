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

// 설계서 화면 22 (TX Code · Empty). PIN 화면과 같은 공용 부품(DigitBoxView · NumberPadView)을 재사용하되,
// PIN 인증 로직(PINViewModel)과는 분리한다. 입력 자릿수는 length 로 가변(tx_code.length 주입 대비).
struct TxCodeView: View {

    @Environment(\.dismiss) var dismiss

    @State private var viewModel: TxCodeViewModel

    var onClose: (() -> Void)?
    var onComplete: (String) -> Void

    init(length: Int = 6,
         description: String = "",
         onClose: (() -> Void)? = nil,
         onComplete: @escaping (String) -> Void) {
        _viewModel = State(wrappedValue: TxCodeViewModel(length: length, description: description))
        self.onClose = onClose
        self.onComplete = onComplete
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(alignment: .leading) {

            Button {
                if let onClose { onClose() } else { dismiss() }
            } label: {
                Image(.icClose)
                    .padding(20)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.title)
                    .font(.pretendard(size: 24, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(viewModel.message)
                    .font(.pretendard(size: 14, weight: .regular))
                    .foregroundStyle(.customGray)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 8)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            VStack(alignment: .center, spacing: 12) {
                Spacer()

                // 오류 상태가 없다 — 코드가 틀리면 이 화면은 그냥 닫히고 호출 화면 위에
                // 다이얼로그가 뜬다(TXC-E-01).
                // tx_code 는 PIN 과 달리 비밀값이 아니라 issuer 가 알려 준 거래 코드다 —
                // 설계서 22/22a 는 입력한 숫자를 가리지 않고 그대로 보여 준다.
                DigitBoxView(maskDigits: false,
                             digits: $viewModel.code,
                             maxDigits: viewModel.length,
                             isErrored: false)

                Spacer()
            }
            .frame(maxWidth: .infinity)

            NumberPadView(
                onDigit: { digit in
                    viewModel.addDigit(digit)
                },
                onDelete: {
                    viewModel.deleteDigit()
                }, onDeleteAll: {
                    viewModel.deleteAllDigits()
                }
            )
            .frame(maxWidth: .infinity)
            .safeAreaPadding(.bottom)
            .padding()
            .onChange(of: viewModel.isCompleted) { _, newValue in
                if newValue {
                    onComplete(viewModel.code)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundGray.ignoresSafeArea())
    }
}

#Preview {
    TxCodeView(length: 6, description: "Enter the 6-digit code sent to you.") { code in
        print("tx_code: \(code)")
    }
}
