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

// 불변 키 식별자 상수 — 값 타입 String 이라 어느 액터에서 읽어도 안전.
// 기본 MainActor 격리(SWIFT_DEFAULT_ACTOR_ISOLATION)를 벗어나 nonisolated 발급/인증
// 경로(BiometricError, UpdateUserProtocol, PINViewModel)에서 경고 없이 참조하도록 한다.
nonisolated struct KeyIdName {
    static let pin:      String = "pin"
    static let bio:      String = "bio"
    static let keyAgree: String = "keyagree"
}
