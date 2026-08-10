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

    // 발급 가능한 VC plan 목록 (TAS /list/api/v1/vcplan/list 결과).
    var plans: [VCPlan] = []

    // 초기 .task 가 발화하기 전 한 프레임 동안 "empty" 메시지가 깜빡이지 않도록 true 시작.
    var isLoading: Bool = true

    func load(coordinator: AppCoordinator) async {
        // 서버에서 plan 목록을 받아오는 구간이므로 인라인 프로그래스가 아니라 로딩 HUD 로 덮는다.
        isLoading = true
        OverlayManager.shared.showLoading()
        defer {
            isLoading = false
            OverlayManager.shared.hideLoading()
        }
        do {
            plans = try await TASConnection.getVCPlanList()
            // DOC-E-01: 발급 가능 Issuer 0건 → 안내 다이얼로그, OK 시 Docs 로 복귀.
            if plans.isEmpty {
                OverlayManager.shared.showPopup(
                    title: "Notification",
                    message: "No issuers available.",
                    primaryButtonTitle: "OK",
                    primaryAction: { coordinator.popToMain() }
                )
            }
        } catch {
            // DOC-E-02: Add list 로딩 실패 → OK 시 호출 화면(Docs)으로 복귀.
            OverlayManager.shared.showErrorPopup(
                title: "Failed to load VC list",
                error: error,
                primaryAction: { coordinator.popToMain() }
            )
        }
    }

    // 사용자가 plan 한 개 선택 → preProcess → 추가정보 웹 폼 → 인증 → process.
    // did-ca 순서 검증: preProcess(propose-issue-vc 등)를 웹폼보다 먼저 실행해 발급
    // 트랜잭션(txId)을 만든 뒤 addVcInfo 가 그 위에 얹히도록 한다 (addVcInfo 입력값 유실 방지).
    // process(핸드셰이크)는 인증 후 실행 — PIN 패드와 메인 스레드 경합 회피.
    // allowedIssuers 비어있는 plan 은 발급 불가 → noOp.
    func pick(_ plan: VCPlan, coordinator: AppCoordinator) async {
        guard plan.allowedIssuers?.first != nil else { return }

        // [1] preProcess — propose-issue-vc 로 발급 트랜잭션 먼저 생성. 사용자 인터랙션이 없는
        //     네트워크 구간이라 로딩 HUD 로 덮는다.
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

        // [2] 추가정보 입력 웹 폼 (DEMO_URL/addVcInfo). 완료(true)면 발급 진행, 실패·취소면 중단.
        do {
            let webFormURL = try IssueVcProtocol.webFormURL(for: plan)
            guard await coordinator.presentIssueWebForm(url: webFormURL) else { return }
        } catch {
            // load/issue 실패와 동일하게 OK 시 Docs 로 복귀 — webFormURL 실패(holder DID 없음/
            // schema id 깨짐)는 같은 plan 재시도해도 재발하므로 화면 잔류가 아니라 복귀가 일관됨.
            OverlayManager.shared.showErrorPopup(
                title: "Failed to open issue form",
                error: error,
                primaryAction: { coordinator.popToMain() }
            )
            return
        }

        // [3] 인증 (PIN/BIO 시트 또는 PIN 입력 모달).
        guard let auth = await coordinator.presentAuth() else { return }

        // [4] process — 인증 후 핸드셰이크(request-issue-vc + confirm).
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
