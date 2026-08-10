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

struct Splash: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var vm = SplashViewModel()

    var body: some View {
        VStack(spacing: 24) {
            Image(.logo)
                .resizable()
                .frame(width: 120, height: 120)

            DotSpinner()
                .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundGray.ignoresSafeArea())
        .task {
            guard let route = await vm.bootstrap() else { return }
            // Unlock PIN 활성 상태면 라우팅 전에 인증을 통과해야 한다.
            // X 버튼·시스템 백은 PINView 측에서 exit(0) (project_unlock_pin_exit).
            if vm.needsLockAuth {
                await coordinator.presentLockAuth()
            }
            switch route {
            case .main:
                // 메인 진입 전에 지갑 VC 를 메모리로 읽어 둔다 — MainView 가 곧장 표시.
                // 온보딩 경로는 holder DID 도 없어 조회할 VC 가 없으므로 스킵.
                coordinator.credentials = await CredentialStore.shared.loadCredentials()
                coordinator.popToMain()
            case .onboarding(let step):
                coordinator.setRoot(.onboarding(step: step))
            }
        }
    }
}

#Preview {
    Splash()
        .environment(AppCoordinator())
}
