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
import DIDWalletSDK

/// SDK 의 단순 상태 질의(isLock / holder DID 존재·id)를 한 곳에 모은다.
/// 이전엔 `WalletAPI.shared.isLock()` / `getDidDocument(...)` 가 Splash·AppRoot·Coordinator
/// 등 여러 화면에 흩어져 있었음 — 의미 주석도 여기서 한 번만 설명한다.
/// (full DIDDocument 나 throwing 이 필요한 서명/토큰 경로는 호출처에 그대로 둔다.)
enum WalletState {

    /// 지갑 잠금(Unlock PIN) 활성 여부. SDK `isLock()` 은 내부적으로 `isRegLock()`
    /// (CoreData `finalEncKey != ""`) 을 반환하는 **persistent** 값이다.
    static var isLockEnabled: Bool {
        (try? WalletAPI.shared.isLock()) ?? false
    }

    /// 현재 holder DID 문자열. 미생성 시 nil.
    static var holderDID: String? {
        (try? WalletAPI.shared.getDidDocument(type: .HolderDidDocumnet))?.id
    }

    /// holder DID 문서 존재 여부 (온보딩 step 분기용).
    static var hasHolderDID: Bool { holderDID != nil }

    /// 발급 웹 화면에 실어 보내는 사용자 식별 값. 온보딩에서 CAS 에 등록한 userId 를 그대로 쓰며,
    /// 서버는 이 값을 사용자 이름 자리로 소비한다 (OpenDID `addVcInfo` 의 `userName`,
    /// OID4VCI user initiation 의 `userName` 이 같은 값 — 두 경로가 갈라지지 않도록 여기서 한 번만 읽는다).
    /// 미바인딩이면 nil.
    static var userName: String? {
        guard let userId = Preference.getUserId(), !userId.isEmpty else { return nil }
        return userId
    }
}
