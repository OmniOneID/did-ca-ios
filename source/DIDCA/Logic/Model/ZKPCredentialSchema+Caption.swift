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

extension ZKPCredentialSchema {

    /// ZKP claim key (`namespace.id.label`) → caption (human-readable label) mapping.
    /// Shared by the detail screen (`CredentialStore`) and the submission screen (`VerifyZKProofProtocol`).
    /// Same pattern as did-ca-ios `VCDetailViewController` / `makeReferentNameMap`.
    var captionMap: [String: String] {
        var dict: [String: String] = [:]
        for attr in attrTypes {
            for item in attr.items {
                dict["\(attr.namespace.id).\(item.label)"] = item.caption
            }
        }
        return dict
    }
}

extension Sequence where Element == ZKPCredentialSchema {

    /// Flattens the captionMaps of several schemas into one. On key collision the later value wins.
    var mergedCaptionMap: [String: String] {
        reduce(into: [String: String]()) { dict, schema in
            dict.merge(schema.captionMap) { _, new in new }
        }
    }
}
