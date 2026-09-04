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

/// 제출 가능한 크리덴셜이 없음 (PRES-E-04).
///
/// **두 경우를 구분하지 않는다** — 요청한 크리덴셜을 아예 보유하지 않은 경우와, 보유하고 있으나
/// ACTIVE 가 0건인 경우(전부 Inactive/Expired)를 같게 다룬다. 사용자가 취할 조치가 상황마다 달라
/// 원인을 단정하지 않기 위해서다.
///
/// 일반 VP(`VerifyVcProtocol`)와 OID4VP(`OID4VPPresenter`)가 같은 것을 던지고, 화면 진입 지점
/// (`QRRouter`)이 한 곳에서 안내 다이얼로그로 바꾼다.
nonisolated struct NoSubmittableCredentialError: Error {
    static let title = "No available certificates"
    static let message = "You don't have a certificate that can be submitted for this request."
}
