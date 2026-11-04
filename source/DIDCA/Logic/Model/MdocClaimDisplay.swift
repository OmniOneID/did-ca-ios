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

/// Shared logic that converts mDoc (ISO/IEC 18013-5) element values for on-screen display.
/// Gathered in one place so list/detail (`CredentialStore`) and the VP request screen (`OID4VPPresenter`) use the same rules
/// — the counterpart of `SdJwtClaimDisplay` on the SD-JWT side.
///
/// Element values are CBOR, not JSON, so they can't be handled as strings only. Three branches matter in particular.
/// - `.bytes` is a byte string. If the name is in the image whitelist and it actually opens as an image, draw it as a picture;
///   otherwise write `"(N bytes)"`. Bytes are not faked as a string.
/// - `.fullDate` is kept **as the string**. It has no time or time zone, so converting it to `Date` can shift it
///   by a day on display (SDK doc section 3).
/// - Only `.dateTime` is an actual point in time, so it is formatted.
///
/// A stateless pure transformation, hence `nonisolated` — the protocol layer calls it off the main actor.
nonisolated enum MdocClaimDisplay {

    /// mDoc card title. Uses the same rule as SD-JWT (`configurationId`) — see `SdJwtClaimDisplay.title`.
    /// docType goes in the issuer slot rather than the title (it is a document kind, not a human-readable name).
    static func title(of item: MdocCredentialItem) -> String {
        item.configurationId
    }

    /// Display value of one element. Composite values (array/map) leave the value slot empty and expand into `childRows`.
    ///
    /// The label is the raw `elementIdentifier` — no namespace is prepended.
    /// The element names the issuer sends already include the namespace, so prefixing would show it twice.
    static func claimValue(name: String, value: MdocElementValue) -> ClaimValue {
        switch value {
        case .bytes(let data):
            // Image detection and the `"(N bytes)"` fallback are both owned by ImageClaim (same place as the per-format detection rules).
            return ImageClaim.claimValue(name: name, data: data)
        case .array, .map:
            return .text("")
        default:
            return .text(scalarString(value))
        }
    }

    /// Scalar element → display string. Composite values and byte strings are an empty string here
    /// (byte strings are handled by `claimValue` as an image or a size notation).
    static func scalarString(_ value: MdocElementValue) -> String {
        switch value {
        case .text(let text):       return text
        case .integer(let number):  return String(number)
        case .double(let number):   return String(number)
        case .bool(let flag):       return flag ? "true" : "false"
        case .fullDate(let date):   return date          // As written by the issuer — do not convert.
        case .dateTime(let date):   return dateTimeFormatter.string(from: date)
        case .bytes, .array, .map, .null:
            return ""
        }
    }

    /// Child items of a composite value (array/map). Empty array for scalars or empty values.
    /// - map   → one row per key. `Dictionary` iteration order varies per run, so sort by key to fix it.
    /// - array → unlabeled rows (label=""). The index is not a value the issuer sent but a number attached to the order.
    ///
    /// If a child is itself composite, its value slot is empty — the screen draws only one level (same rule as the SD-JWT side).
    static func childRows(_ value: MdocElementValue) -> [(label: String, value: ClaimValue)] {
        switch value {
        case .map(let keyValues):
            return keyValues.sorted { $0.key < $1.key }
                .map { (label: $0.key, value: claimValue(name: $0.key, value: $0.value)) }
        case .array(let elements):
            return elements.map { (label: "", value: claimValue(name: "", value: $0)) }
        default:
            return []
        }
    }

    /// `.dateTime` notation — the date part has the same shape as the list's ISSUED / VALID UNTIL, and since it is an actual
    /// point in time, hours and minutes are appended. Time zone is device-local (the issuer's value is a UTC-based instant itself).
    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd MMM yyyy HH:mm"
        return formatter
    }()
}
