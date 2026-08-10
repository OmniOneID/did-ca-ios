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

struct Banner: Identifiable {
    let id = UUID()
    let name: String
}

struct BiometricsView : View {

    @State private var vm = BiometricsViewModel()

    var isFromSettings: Bool = false
    var onEnable: () -> Void = {}
    var onSkip: () -> Void = {}

    let banners = [
        Banner(name: "icFingerLarge"),
        Banner(name: "icFace"),
    ]
    
    var body: some View {
        VStack(alignment: .center) {

            Spacer()

            VStack(alignment: .center, spacing: 24) {
                Circle()
                    .frame(width: 200, height: 200)
                    .foregroundStyle(.white)
                    .shadow(color: .primaryShadow.opacity(0.1), radius: 10, x: 0, y: 6)
                    .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
                    .overlay {
                        TripleBufferInfiniteCarousel(
                            items: banners,
                            interval: 2.5,
                            initialDelay: .milliseconds(300),
                            animationDuration: 0.35,
                            isUserInteractionEnabled: false
                        ) { item in
                            Image(item.name)
                                .aspectRatio(contentMode: .fit)
                                .padding(52)
                        }
                        .clipShape(Circle())
                    }

                Text("Set up biometrics")
                    .font(.pretendard(size: 24, weight: .bold))
                    .foregroundStyle(.black)

                Text("Register biometric authentication to sign in\nquickly with your fingerprint or face instead\nof your PIN.")
                    .font(.pretendard(size: 14, weight: .regular))
                    .foregroundStyle(.customGray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)


            }

            Spacer()

            VStack(spacing: 8) {
                Button {
                    // 설정 경로는 키 생성 + 문서 갱신을 coordinator(addBiometricsFromSettings →
                    // UpdateUserProtocol.addBioKey) 가 담당하므로, 여기선 enable 신호만 보낸다.
                    // 온보딩은 기존대로 ViewModel 에서 bio 키만 생성 (뒤이어 step2 가 문서 생성).
                    if isFromSettings {
                        onEnable()
                    } else {
                        Task { await vm.enable(onSuccess: onEnable) }
                    }
                } label: {
                    Text("Enable Biometrics")
                        .font(.pretendard(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(height: 52)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .foregroundStyle(.customPrimary)
                        )
                        .shadow(color: .customPrimary.opacity(0.3), radius: 3, x: 0, y: 2)
                }

                Button {
                    onSkip()
                } label: {
                    Text((isFromSettings) ? "Cancel" : "Skip" )
                        .font(.pretendard(size: 16, weight: .semibold))
                        .foregroundStyle(.customPrimary)
                        .frame(height: 48)
                        .frame(maxWidth: .infinity)

                }




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
    BiometricsView()
}

