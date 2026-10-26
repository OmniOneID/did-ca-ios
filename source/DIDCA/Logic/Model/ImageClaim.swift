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


import UIKit
import DIDWalletSDK

/// Image claim (portrait etc.) detection and value decoding — design spec VC-B-01 / VC-B-03.
///
/// **The detection criterion differs per format.**
/// - SD-JWT / mDoc: only the claim **name whitelist** is checked. These are formats whose issuance-metadata type info can't be trusted.
/// - W3C (OpenDID) VC: uses the `claim.type` carried in the data model as-is. More accurate than guessing by name, and
///   existing image claims issued under names outside the whitelist don't regress to text.
///   (The design spec says "detect by name whitelist only", but that is the Android/EUDI mDoc basis — iOS
///   splits by format. User decision 2026-08-11.)
///
/// Even when detection differs, **the value decoding rules are shared**, and no error dialog is shown in any case
/// (an empty optional item is a normal state). The fallback display depends on what remains — name detection (SD-JWT)
/// shows the original text since it is the value itself; mDoc has only bytes, so `"(N bytes)"`; with type detection (W3C),
/// if declared as an image but it won't open, the original is several KB of base64, so it isn't used and `"—"` is shown.
/// A stateless pure transformation, hence `nonisolated` — the protocol layer (`OID4VPPresenter` etc.) calls it
/// while building card lists off the main actor.
nonisolated enum ImageClaim {

    /// Claim names to draw as images. Same list as the EUDI reference wallet.
    private static let imageNames: Set<String> = ["portrait", "picture", "signature_usual_mark"]

    /// Whether the name is in the whitelist — compared only by the **segment after the last `.`**.
    /// Recognized the same even if the issuer prefixes a namespace (`eu.europa.ec.eudi.pid.1.portrait`).
    static func isImageName(_ claimName: String) -> Bool {
        let segment = claimName.split(separator: ".").last.map(String.init) ?? claimName
        return imageNames.contains(segment.lowercased())
    }

    /// Display value of one SD-JWT / mDoc claim — `.image` if the name is in the whitelist and the value reads as an image,
    /// otherwise `.text` (original as-is).
    static func claimValue(name: String, text: String) -> ClaimValue {
        guard isImageName(name), let data = decode(text) else { return .text(text) }
        return .image(data)
    }

    /// Display value of one mDoc element — the value is already bytes, so there is nothing to decode.
    ///
    /// If it doesn't open as an image, write `"(N bytes)"` (design spec VC-B-01). The SD-JWT/W3C fallback is "the original
    /// text", but there is no original text here — faking bytes as a string leaves only garbled characters.
    static func claimValue(name: String, data: Data) -> ClaimValue {
        guard isImageName(name), !data.isEmpty, UIImage(data: data) != nil else {
            return .text("(\(data.count) bytes)")
        }
        return .image(data)
    }

    /// Display value of one W3C (OpenDID) VC claim — detection uses `claim.type`.
    ///
    /// For non-image claims the original text is the display value. However, **if declared as an image but it won't open,
    /// the original is not used** — it is several KB of base64 and would spill entirely into the label slot. It isn't
    /// human-readable, so fall back to an empty-value display (same intent as `"(N bytes)"` in `claimValue(name:data:)`).
    static func claimValue(type: ClaimType, encoded: String) -> ClaimValue {
        guard type == .image else { return .text(encoded) }
        guard let data = decode(encoded) else { return .text(unreadableImageText) }
        return .image(data)
    }

    /// Display value when a claim declared as an image won't open as an image.
    private static let unreadableImageText = "—"

    /// Encoded value → image `Data`. nil if it doesn't read as an image.
    ///
    /// Accepted forms: base64 with a `data:` URI prefix, standard / URL-safe base64, multibase.
    /// Even after decoding succeeds, also check that it **actually opens as an image** (`UIImage`) — arbitrary strings
    /// often decode as base64 too, so without this check text would masquerade as an empty image cell.
    static func decode(_ encoded: String) -> Data? {
        let payload = strippingDataURIPrefix(encoded)
        guard !payload.isEmpty else { return nil }   // An empty value is a normal state — it is a fallback target.

        let decoded = base64Decoded(payload) ?? (try? MultibaseUtils.decode(encoded: payload))
        guard let decoded, !decoded.isEmpty, UIImage(data: decoded) != nil else { return nil }
        return decoded
    }

    /// Strips a prefix like `data:image/png;base64,` leaving only the payload. Returns the original if there is no prefix.
    private static func strippingDataURIPrefix(_ value: String) -> String {
        guard value.hasPrefix("data:"), let comma = value.firstIndex(of: ",") else { return value }
        return String(value[value.index(after: comma)...])
    }

    /// Tries standard base64 first; on failure converts URL-safe (`-`/`_`) back to standard and tries once more.
    /// Also restores notation with omitted padding (`=`).
    private static func base64Decoded(_ value: String) -> Data? {
        if let data = Data(base64Encoded: value) { return data }

        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder > 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: normalized)
    }
}
