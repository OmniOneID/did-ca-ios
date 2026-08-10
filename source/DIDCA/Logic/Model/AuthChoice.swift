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

// 발급 흐름 등에서 사용자가 어떤 인증 방식으로 서명할지를 표현.
//   .pin(_) : PIN 인증 완료 — 입력된 passcode 동봉
//   .bio    : 바이오 인증 선택 — passcode 없음. SDK 가 getSignedDidAuth(passcode: nil) 호출 시점에
//             bio 키 사용하면서 iOS 가 FaceID/TouchID prompt 자동 표시.
enum AuthChoice {
    case pin(String)
    case bio

    var passcode: String? {
        if case .pin(let p) = self { return p }
        return nil
    }
}

// 선택 시트가 사용자 픽을 결과로 돌려줄 때만 쓰는 중간 타입.
// presentAuth 내부에서 이 픽을 받아 PIN 모달로 체이닝하거나 .bio 로 그대로 매핑.
enum AuthSelectionPick {
    case pin
    case bio
}
