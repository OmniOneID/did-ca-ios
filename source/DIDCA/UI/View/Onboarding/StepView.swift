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

struct TitleMessage {
    let title: String
    let message: String
}

enum StepEnum : Int
{
    case step1 = 1
    case step2
    case step3
    
    func getIcon() -> ImageResource
    {
        switch self
        {
        case .step1:
            return .icUser
        case .step2:
            return .icLock
        case .step3:
            return .icSign
        }
    }
    
    func getTitle() -> String
    {
        switch self
        {
        case .step1:
            return "User Setup"
        case .step2:
            return "Signature Key"
        case .step3:
            return "Authentication"
        }
    }
    
    func getDescriptions() -> [TitleMessage]
    {
        switch self
        {
        case .step1:
            return [
                .init(
                    title: "Register Demo User",
                    message: "Handled automatically on the backend — no input required."
                ),
                .init(
                    title: "Set Wallet Lock",
                    message: "Choose how to secure your wallet."
                )
            ]
        case .step2:
            return [
                .init(
                    title: "Register PIN",
                    message: "Your PIN is used to generate a signature key for the wallet."
                ),
                .init(
                    title: "Register DID Document",
                    message: "A DID document is created to identify your wallet on-chain."
                )
            ]
            
        case .step3:
            return [
                .init(
                    title: "Authenticate to Sign",
                    message: "Confirm your identity to sign documents tied to your DID."
                )
            ]
        }
    }
}

struct StepView : View {

    @Environment(AppCoordinator.self) private var coordinator
    @State private var vm = StepViewModel()

    var step : StepEnum

    var body: some View {
        VStack(spacing: 20) {

            Circle()
                .frame(width: 120, height: 120)
                .foregroundStyle(.white)
                .shadow(color: .primaryShadow.opacity(0.1), radius: 10, x: 0, y: 6)
                .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
                .overlay {
                    Image(step.getIcon())
                        .frame(width: 56, height: 56)
                }

            Text(step.getTitle())
                .font(.pretendard(size: 22, weight: .semibold))
                .foregroundStyle(.black)

            VStack(spacing: 10) {
                ForEach(0..<step.getDescriptions().count, id: \.self) { raw in
                    HStack(alignment: .top, spacing: 14) {

                        Circle()
                            .frame(width: 26, height: 26)
                            .foregroundStyle(.customPrimary)
                            .overlay {
                                Text("\(raw + 1)")
                                    .font(.pretendard(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                            }

                        let titleMessage = step.getDescriptions()[raw]
                        VStack(alignment: .leading, spacing: 4) {
                            Text(titleMessage.title)
                                .font(.pretendard(size: 14, weight: .semibold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity,alignment: .leading)
                            Text(titleMessage.message)
                                .font(.pretendard(size: 12, weight: .regular))
                                .foregroundStyle(.customGray)
                                .frame(maxWidth: .infinity,alignment: .leading)
                        }
                    }
                    .padding(16)
                    .background(content: {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.paleOrange)
                            .stroke(
                                .borderOrange,
                                lineWidth: 1
                            )
                    })
                }
            }


            Spacer()

            Text("STEP \(step.rawValue) OF 3")
                .font(.pretendard(size: 11, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(.customGray)
                .frame(maxWidth:.infinity, alignment: .leading)

            HStack(spacing: 6) {
                Capsule()
                    .frame(height:6)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.customPrimary)

                Capsule()
                    .frame(height:6)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(
                        (step.rawValue > StepEnum.step1.rawValue ? .customPrimary : .paleOrange)
                    )

                Capsule()
                    .frame(height:6)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(
                        (step.rawValue == StepEnum.step3.rawValue ? .customPrimary : .paleOrange)
                    )
            }
            .padding(.bottom, 10)

            Button {
                vm.handleNext(step: step, coordinator: coordinator)
            } label: {
                Text("NEXT")
                    .font(.pretendard(size: 16, weight: .semibold))
                    .frame(height: 52)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.white)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .foregroundStyle(.customPrimary)
                    }
                    .shadow(color: .customPrimary.opacity(0.3), radius: 3, x: 0, y: 2)
            }


        }
        .padding(.top, 32)
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundGray.ignoresSafeArea())
    }
}

#Preview {
    StepView(step: .step3)
        .environment(AppCoordinator())
}
