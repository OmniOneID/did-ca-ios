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

/// **The set of Custom entries and their values** saved by the Server URL screen.
///
/// The unit of storage is one thing: "which endpoints are Custom + their values". Default entries use the build
/// defaults as is and aren't stored — if only the 6 values were stored, a custom value that happens to equal the default
/// couldn't be restored to the Custom section on re-entry. Key present means Custom; absent means Default.
///
/// Saved values are used for networking **immediately on save** — no launch-time snapshot; read every time.
/// In-flight requests complete with the URL already built; requests after that use the new address.
nonisolated enum ServerURLStore {

    private static let defaults = UserDefaults.standard
    private static var key: String { PreferenceKey.serverURLs.rawValue }

    /// The value network callers see — used only through `URLs`. The saved value if Custom, otherwise the build default.
    static func value(_ endpoint: ServerEndpoint) -> String {
        customValues()[endpoint] ?? endpoint.defaultValue
    }

    /// The saved Custom set — the basis for restoring sections on screen entry and the dirty check.
    static func customValues() -> [ServerEndpoint: String] {
        let stored = (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
        return stored.reduce(into: [:]) { acc, pair in
            guard let endpoint = ServerEndpoint(rawValue: pair.key) else { return }
            acc[endpoint] = pair.value
        }
    }

    /// Saves the whole Custom set. If empty, removes the key itself (= all Default).
    ///
    /// - Returns: Whether the save succeeded. `UserDefaults` writes don't throw, so it reads back to confirm
    ///   (the only way to detect "save failed").
    @discardableResult
    static func save(custom: [ServerEndpoint: String]) -> Bool {
        let trimmed = custom.reduce(into: [ServerEndpoint: String]()) { acc, pair in
            acc[pair.key] = normalize(pair.value)
        }
        if trimmed.isEmpty {
            clear()
            return customValues().isEmpty
        }
        let raw = trimmed.reduce(into: [String: String]()) { $0[$1.key.rawValue] = $1.value }
        defaults.setValue(raw, forKey: key)
        return customValues() == trimmed
    }

    /// Deletes the Custom set — all 6 return to build defaults. Also called by app reset.
    static func clear() {
        defaults.removeObject(forKey: key)
    }

    /// Normalization right before saving — trims surrounding whitespace and the **trailing `/`**. Callers all append paths
    /// with a leading `/` like `URLs.X + "/tas/api/…"`, so saving `http://host:8090/` would turn every request into a `//` path.
    static func normalize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces)
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }
}
