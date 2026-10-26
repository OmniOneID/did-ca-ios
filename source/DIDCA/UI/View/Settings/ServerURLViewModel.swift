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


import SwiftUI
import Observation

/// State of the Server URL screen (design spec 29a~29d · SRV-01~09 · SRV-E-01~08).
///
/// The screen state is a single thing: **"which endpoints are in the Custom section and what their values are"** (`custom`).
/// Endpoints without a key are in the Default section and use the build default as is, so they aren't held separately.
/// Save, dirty and validity checks all look at this one set (SRV-09).
@Observable
final class ServerURLViewModel {

    /// Saved values at the time the screen was entered — the baseline for the dirty check (SRV-09).
    private let saved: [ServerEndpoint: String]

    private(set) var custom: [ServerEndpoint: String]
    /// Holds only Custom endpoints with format errors — empty means no errors.
    private(set) var errors: [ServerEndpoint: String] = [:]

    init() {
        saved = ServerURLStore.customValues()
        custom = saved
    }

    // MARK: - Sections

    /// Both sections keep the fixed endpoint order — the order doesn't change even when items move (SRV-02).
    var customList: [ServerEndpoint] { ServerEndpoint.allCases.filter { custom[$0] != nil } }
    var defaultList: [ServerEndpoint] { ServerEndpoint.allCases.filter { custom[$0] == nil } }

    /// Default → Custom (SRV-04) — moves it up as editable, pre-filled with the build default. Doesn't start blank.
    func toCustom(_ endpoint: ServerEndpoint) {
        custom[endpoint] = endpoint.defaultValue
        errors[endpoint] = nil
    }

    /// Custom → Default (SRV-06) — the custom value is discarded without confirmation. It's before save, so easy to undo.
    func toDefault(_ endpoint: ServerEndpoint) {
        custom[endpoint] = nil
        errors[endpoint] = nil
    }

    /// Moves the whole Default section to Custom (SRV-04). Values of items already in Custom are untouched.
    func allToCustom() {
        for endpoint in defaultList { toCustom(endpoint) }
    }

    /// Moves the whole Custom section to Default (SRV-06) = restore all build defaults. Performed without confirmation.
    func allToDefault() {
        custom = [:]
        errors = [:]
    }

    // MARK: - Input

    func binding(for endpoint: ServerEndpoint) -> Binding<String> {
        Binding(get: { self.custom[endpoint] ?? "" },
                set: { self.setValue($0, for: endpoint) })
    }

    /// Format check right on input (SRV-05 · SRV-E-01~03).
    private func setValue(_ value: String, for endpoint: ServerEndpoint) {
        custom[endpoint] = value
        errors[endpoint] = Self.validate(value)
    }

    // MARK: - Checks

    /// Save enabled condition (SRV-09) — when the Custom set or its values differ from the saved ones, and Custom fields have no format errors.
    /// Just moving sections changes the saved result, so it counts as a change. The Default section isn't checked.
    var canSave: Bool { isDirty && !hasError }

    var isDirty: Bool { custom != saved }

    var hasError: Bool { customList.contains { errors[$0] != nil } }

    // MARK: - Actions

    /// Save (SRV-07). Returns false on failure — the caller shows the SRV-E-05 notice.
    func save() -> Bool {
        ServerURLStore.save(custom: custom)
    }

    // MARK: - Format check (SRV-E-01 · E-02 · E-03)

    /// nil if it passes, otherwise the inline message to attach below the field.
    static func validate(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Enter a URL." }
        guard ServerURLParts.parse(trimmed) != nil else {
            // Only split into the port message when the port part isn't numeric or is out of range (SRV-E-02).
            return ServerURLParts.hasPortProblem(trimmed)
                ? "Port must be between 1 and 65535."
                : "Enter a valid URL starting with http:// or https://."
        }
        return nil
    }
}

/// One `http(s)://host[:port][/path]` unit. URLComponents lumps a non-numeric port and a
/// scheme typo into the same failure, making SRV-E-01/E-02 indistinguishable, so we split it ourselves.
struct ServerURLParts {
    let scheme: String
    let host: String
    let port: Int?
    let path: String

    static func parse(_ raw: String) -> ServerURLParts? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }

        let lowered = trimmed.lowercased()
        let scheme: String
        if lowered.hasPrefix("https://") { scheme = "https" }
        else if lowered.hasPrefix("http://") { scheme = "http" }
        else { return nil }

        let rest = String(trimmed.dropFirst(scheme.count + 3))
        guard !rest.isEmpty else { return nil }

        let authority: Substring
        let path: String
        if let slash = rest.firstIndex(of: "/") {
            authority = rest[rest.startIndex..<slash]
            path = String(rest[slash...])
        } else {
            authority = rest[...]
            path = ""
        }

        let pieces = authority.split(separator: ":", omittingEmptySubsequences: false)
        guard let host = pieces.first, !host.isEmpty, pieces.count <= 2 else { return nil }

        var port: Int?
        if pieces.count == 2 {
            guard let value = Int(pieces[1]), (1...65535).contains(value) else { return nil }
            port = value
        }
        return ServerURLParts(scheme: scheme, host: String(host), port: port, path: path)
    }

    /// Whether a value that failed to parse failed **because of the port** — used only to choose the error message.
    static func hasPortProblem(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let lowered = trimmed.lowercased()
        guard lowered.hasPrefix("http://") || lowered.hasPrefix("https://") else { return false }
        let scheme = lowered.hasPrefix("https://") ? "https" : "http"
        let rest = String(trimmed.dropFirst(scheme.count + 3))
        let authority = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let pieces = authority.split(separator: ":", omittingEmptySubsequences: false)
        guard pieces.count == 2, !pieces[0].isEmpty else { return false }
        guard let value = Int(pieces[1]) else { return true }
        return !(1...65535).contains(value)
    }
}
