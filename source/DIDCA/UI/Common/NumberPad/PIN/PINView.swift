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

public typealias CURRENTPIN = String
public typealias NEWPIN = String

struct PINView: View {
    
    @Environment(\.dismiss) var dismiss
    
    @State private var viewModel: PINViewModel
    
    var onClose: (() -> Void)?
    var onSuccess: ((CURRENTPIN, NEWPIN) -> Void)//current, new
    init(mode: PINMode, onClose: (() -> Void)? = nil, onSuccess: @escaping (CURRENTPIN, NEWPIN) -> Void ){
        _viewModel = State(wrappedValue: PINViewModel(mode: mode))
        self.onClose = onClose
        self.onSuccess = onSuccess
    }
    
    var body: some View {
        @Bindable var viewModel = viewModel
        
        VStack(alignment: .leading){
            
            Button {
                if let onClose { onClose() } else { dismiss() }
            } label: {
                Image(.icClose)
                    .padding(20)
            }
//            .background(.red)
            
            VStack(alignment: .leading, spacing: 6) {


                Text(LocalizedStringResource(stringLiteral: viewModel.title))
                    .font(.pretendard(size: 24, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(LocalizedStringResource(stringLiteral:viewModel.message))
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
                
                DigitBoxView(maskDigits: true,
                             digits: $viewModel.tempPIN,
                             isErrored: viewModel.errorMessage != nil)
    //            .padding(.bottom, 20)
                if let error = viewModel.errorMessage
                {
                    Text(error)
                        .font(.pretendard(size: 13, weight: .medium))
                        .foregroundStyle(.customRed)
                        .multilineTextAlignment(.leading)
                }
                
                
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
            .onChange(of: viewModel.completionToken) { _, newValue in
                // The token is a new UUID on every completion, so even if the caller keeps the screen and reports a failure,
                // it fires every time the user completes again. Calling dismiss() here would break the coordinator's
                // modal content swap, so closing remains the caller's job.
                if newValue != nil {
                    onSuccess(viewModel.currentPIN, viewModel.newPIN)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundGray.ignoresSafeArea())
    }
}

#Preview {
    Group {
        PINView(mode: .create()) { current, new in
            ()
        }
    }
}

