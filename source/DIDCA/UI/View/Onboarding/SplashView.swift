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

            // SPL-01 — hide the spinner while the server settings popup is shown (its space is kept).
            DotSpinner()
                .padding()
                .opacity(vm.isServerSetupPending ? 0 : 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundGray.ignoresSafeArea())
        .task {
            await vm.promptServerSetupIfNeeded(coordinator: coordinator)
            // Pushing the Server URL screen (SPL-03) covers Splash and cancels this task; returning via pop starts
            // a new task. A cancelled task that received the answer backs off here and leaves initialization/routing to the new task —
            // if both proceeded, createWallet would silently die with -999 or setRoot would be called twice.
            guard !Task.isCancelled else { return }
            guard let route = await vm.bootstrap(coordinator: coordinator) else { return }
            guard !Task.isCancelled else { return }
            // If Unlock PIN is active, authentication must pass before routing.
            // X button · system back do exit(0) on the PINView side (project_unlock_pin_exit).
            if vm.needsLockAuth {
                await coordinator.presentLockAuth()
            }
            switch route {
            case .main:
                // Load wallet VCs into memory before entering main — MainView displays them right away.
                // The onboarding path has no holder DID and thus no VCs to query, so skip.
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
