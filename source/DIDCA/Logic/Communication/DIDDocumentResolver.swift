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

// MARK: - Version-specific DID Document lookup + in-memory cache
//
// The DID Document used for signature verification must be **the same version as the versionId in the kid**. Even with the
// same fragment (`#assert`), a different version doesn't guarantee the same key, so substituting the latest would misjudge a
// valid signature as forged (a server–client mutual contract).
//
// Once the version is pinned the document is immutable, so the cache can't go stale — no TTL, no version comparison,
// no refetch after a verification failure. Unlike the status cache cleared on returning from background, this cache is kept
// and only cleared when the wallet is reset.
//
// Fetching the latest (no versionId) is intentionally unsupported. It's mutable so it can't be cached under the same rule,
// and for the flow that would need it (token-related certVc verification), whether the latest is required is not yet decided.
actor DIDDocumentResolver {

    static let shared = DIDDocumentResolver()
    private init() {}

    private struct Key: Hashable {
        let did: String
        let versionId: String
    }

    private var cache: [Key: DIDDocument] = [:]

    /// DID Document of the specified version. If cached, no network request is made.
    /// Fetch failures are not cached, so the next call retries.
    func resolve(did: String, versionId: String) async throws -> DIDDocument {
        let key = Key(did: did, versionId: versionId)
        if let cached = cache[key] {
            return cached
        }
        let document = try await CommunicationClient.getDIDDocument(hostUrlString: URLs.API_URL,
                                                                   did: did,
                                                                   versionId: versionId)
        cache[key] = document
        return document
    }

    /// For wallet reset. The document itself is public, but no trace of the previous wallet is left behind.
    func removeAll() {
        cache.removeAll()
    }
}
