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


import Foundation
import Observation
import DIDWalletSDK

@Observable
final class AddCertificateViewModel {

    // List of issuable VC plans (result of TAS /list/api/v1/vcplan/list).
    var plans: [VCPlan] = []

    // Starts true so the "empty" message doesn't flicker for one frame before the initial .task fires.
    var isLoading: Bool = true

    func load(coordinator: AppCoordinator) async {
        // This span fetches the plan list from the server, so it's covered with the loading HUD rather than an inline progress.
        isLoading = true
        OverlayManager.shared.showLoading()
        defer {
            isLoading = false
            OverlayManager.shared.hideLoading()
        }
        do {
            plans = try await TASConnection.getVCPlanList()
            // 0 issuable Issuers → notice dialog, return to Docs on OK.
            if plans.isEmpty {
                OverlayManager.shared.showPopup(
                    title: "Notification",
                    message: "No issuers available.",
                    primaryButtonTitle: "OK",
                    primaryAction: { coordinator.popToMain() }
                )
            }
        } catch {
            // Add list load failed → return to the calling screen (Docs) on OK.
            OverlayManager.shared.showErrorPopup(
                title: "Failed to load VC list",
                error: error,
                primaryAction: { coordinator.popToMain() }
            )
        }
    }

    // User picks one plan → preProcess → additional-info web form → auth → process.
    // Verified did-ca order: run preProcess (propose-issue-vc, etc.) before the web form to create the issuance
    // transaction (txId), so addVcInfo builds on top of it (prevents losing addVcInfo input).
    // process (handshake) runs after auth — avoids main-thread contention with the PIN pad.
    // A plan with empty allowedIssuers can't be issued → noOp.
    func pick(_ plan: VCPlan, coordinator: AppCoordinator) async {
        guard plan.allowedIssuers?.first != nil else { return }
        guard coordinator.canStartWebIssuance() else { return }

        // [1] preProcess — create the issuance transaction first via propose-issue-vc. A network span with no
        //     user interaction, so it's covered with the loading HUD.
        let proto: IssueVcProtocol
        OverlayManager.shared.showLoading()
        do {
            proto = try await IssueVcProtocol.begin(plan: plan)
        } catch {
            OverlayManager.shared.hideLoading()
            OverlayManager.shared.showErrorPopup(
                title: "Failed to start issuance",
                error: error,
                primaryAction: { coordinator.popToMain() }
            )
            return
        }
        OverlayManager.shared.hideLoading()

        // [2] Additional-info input web form (DEMO_URL/addVcInfo). If completed (true), proceed with issuance; on failure/cancel, stop.
        do {
            let webFormURL = try IssueVcProtocol.webFormURL(for: plan)
            guard await coordinator.presentIssueWebForm(url: webFormURL) else { return }
        } catch {
            // Same as load/issue failure, return to Docs on OK — webFormURL failures (no holder DID /
            // broken schema id) recur even when retrying the same plan, so returning is more consistent than staying.
            OverlayManager.shared.showErrorPopup(
                title: "Failed to open issue form",
                error: error,
                primaryAction: { coordinator.popToMain() }
            )
            return
        }

        // [3] Auth (PIN/BIO sheet or PIN input modal).
        guard let auth = await coordinator.presentAuth() else { return }

        // [4] process — handshake after auth (request-issue-vc + confirm).
        OverlayManager.shared.showLoading()
        defer { OverlayManager.shared.hideLoading() }
        do {
            let vcId = try await proto.process(passcode: auth.passcode)
            await coordinator.completeIssuance(vcId: vcId)
        } catch {
            coordinator.failIssuance(error)
        }
    }
}
