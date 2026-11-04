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

// TX Code input screen. Reuses the same shared parts as the PIN screen (DigitBoxView · NumberPadView),
// but is separate from the PIN auth logic (PINViewModel). The digit count varies with length (prepared for tx_code.length injection).
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
            .accessibilityIdentifier("closeButton")

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

                // There is no error state — if the code is wrong this screen just closes and a dialog
                // appears on top of the calling screen.
                // Unlike a PIN, tx_code isn't a secret but a transaction code given by the issuer —
                // The entered digits are shown as is, without masking.
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
