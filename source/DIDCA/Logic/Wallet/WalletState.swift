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

/// Gathers the SDK's simple state queries (isLock / holder DID existence·id) in one place.
/// Previously `WalletAPI.shared.isLock()` / `getDidDocument(...)` were scattered across Splash·AppRoot·Coordinator
/// and other screens — the semantic notes are also explained once, here.
/// (Signing/token paths that need the full DIDDocument or throwing stay at their call sites.)
enum WalletState {

    /// Whether the wallet lock (Unlock PIN) is active. SDK `isLock()` internally returns `isRegLock()`
    /// (CoreData `finalEncKey != ""`), a **persistent** value.
    static var isLockEnabled: Bool {
        (try? WalletAPI.shared.isLock()) ?? false
    }

    /// The current holder DID string. nil if not yet created.
    static var holderDID: String? {
        (try? WalletAPI.shared.getDidDocument(type: .HolderDidDocumnet))?.id
    }

    /// Whether the holder DID document exists (for onboarding step branching).
    static var hasHolderDID: Bool { holderDID != nil }

    /// The user name sent to the issuance web page. Uses the username from the onboarding registration webview as is
    /// (OpenDID `addVcInfo`'s `userName` and OID4VCI user initiation's `userName` are the same value — read once here so
    /// the two paths don't diverge).
    ///
    /// nil if there is no username, and issuance is blocked with an error — it is not filled with userId instead.
    static var userName: String? {
        guard let userName = Preference.getUserName(), !userName.isEmpty else { return nil }
        return userName
    }
}
