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
import CryptoKit
import DIDWalletSDK

/// Status List status values (`draft-ietf-oauth-status-list-21`, server default bits=2).
enum StatusListStatus: Int {
    case valid = 0
    case invalid = 1
    case suspended = 2
    /// Reserved. The server does not use it; if encountered, it is not treated as valid.
    case reserved = 3
}

enum StatusListError: Error {
    /// The status reference is malformed (no uri / idx is not a non-negative integer).
    case invalidReference
    /// The lookup address is not http or https.
    case unsupportedURIScheme
    /// Fetching the Status List Token returned a non-2xx response.
    case fetchFailed(Int)
    /// The response is not a compact JWS, or its header deviates from the spec (typ ≠ statuslist+jwt / alg ≠ ES256 / no kid).
    case invalidToken
    // Signer identity failures propagate as `JWSSignerError` unchanged — kid convention violation, signing
    // key not found, signature mismatch. Not specific to this flow: every place that verifies a JWS by kid throws the same.
    /// The payload's sub differs from the uri the credential points to.
    case subjectMismatch
    /// The token has expired, or its issued-at time is in the future.
    case tokenExpired
    /// The status_list structure violates the spec (bits outside allowed values / lst decode or decompress failure / idx out of range).
    case invalidStatusList
    /// RESERVED(3) — not treated as a valid credential.
    case reservedStatus
}

// MARK: - Status List Token verification (IETF Token Status List)
//
// Integration guide ("Status List client integration guide", based on draft-ietf-oauth-status-list-21) §3·§4.
// Fetches the public Status List Token via the credential's `status.status_list.{uri, idx}`, verifies its
// signature, and returns only the status bits at that index. SD-JWT and mDoc follow the same spec, so they share
// this single path — the SDK reads the reference per format and hands it over as `StatusListReference`.
//
//   [1] status(for:)       GET uri → verify JWS → check sub/exp/iat → decompress lst → extract idx bits
//   [2] statuses(for:)     multiple entries pointing at the same uri fetch the token once and read per index
//
// **Only a single status enum is returned** — neither the raw token nor the decompressed status array is kept.
// Lookup and verification failures are not swallowed; they throw. The caller (CredentialStore) does not substitute
// "valid" but falls back to expiry-date display + a notice (guide §5 — never treat failure as VALID).
nonisolated enum StatusListVerifier {

    /// Status List location the credential points to — the SDK provides the same type for both SD-JWT and mDoc.
    /// The app does not build it by digging through the payload/MSO itself (`SDJWT.status()` / `Mdoc.status`).
    typealias Reference = StatusListReference

    /// Status lookup — fetches and verifies the token, then returns the status at the given index.
    /// The lookup always goes to the server (no HTTP cache).
    static func status(for reference: Reference) async throws -> StatusListStatus {
        let list = try await verifiedList(uri: reference.uri)
        return try Self.status(in: list, index: reference.idx)
    }

    /// Determines the status of several credentials at once — **entries pointing at the same uri fetch the token
    /// only once**, verify it, and read only per-index bits (a wallet's SD-JWTs usually share the same list).
    /// The verified token and decompressed array are discarded when this call ends; the caller is left with status enums only.
    /// Each result is returned as a per-entry `Result` so an individual failure does not block other credentials.
    static func statuses(for references: [String: Reference]) async -> [String: Result<StatusListStatus, Error>] {
        var result: [String: Result<StatusListStatus, Error>] = [:]
        let byURI = Dictionary(grouping: references, by: { $0.value.uri })

        for (uri, entries) in byURI {
            do {
                let list = try await verifiedList(uri: uri)
                for (id, reference) in entries {
                    result[id] = Result { try Self.status(in: list, index: reference.idx) }
                }
            } catch {
                for (id, _) in entries {
                    result[id] = .failure(error)
                }
            }
        }
        return result
    }

    /// Fully verified status array — the decompressed bytes and bits per entry.
    private struct VerifiedList {
        let bytes: Data
        let bits: Int
    }

    /// Fetch token → verify header, signature, `sub`, lifetime → decompress `lst`. Does not interpret the index.
    private static func verifiedList(uri: String) async throws -> VerifiedList {
        guard let url = URL(string: uri),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            throw StatusListError.unsupportedURIScheme
        }

        // The server sends `Cache-Control: max-age=300`, but this token is not cached — a stale value would delay
        // revocation/suspension by up to 5 minutes. The SDK `CommunicationClient` sends only via a dedicated ephemeral
        // session (no urlCache + `reloadIgnoringLocalCacheData`), so it is used as is.
        // The default headers include `Content-Type: application/json`, which doesn't fit a GET, so only Accept is passed.
        let (data, statusCode) = try await CommunicationClient.sendRequest(
            urlString: url.absoluteString,
            httpMethod: .GET,
            headerFields: [
                "Accept": "application/statuslist+jwt",
                "Accept-Language": Locale.preferredLanguages.first ?? "en-US"
            ]
        )
        guard statusCode == 200 else {
            throw StatusListError.fetchFailed(statusCode)
        }
        guard let compact = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !compact.isEmpty
        else {
            throw StatusListError.invalidToken
        }

        // Raw segments (signing input) come from the SDK JWS; header/payload parsing comes from SimpleJWTDecoder.
        let jws = try JWS(from: compact)
        guard let decoded = try? SimpleJWTDecoder.parse(compact) else {
            throw StatusListError.invalidToken
        }

        guard decoded.header["typ"] as? String == "statuslist+jwt",
              decoded.header["alg"] as? String == "ES256",
              let kid = decoded.header["kid"] as? String, !kid.isEmpty
        else {
            throw StatusListError.invalidToken
        }

        // Issuer identity check — verify with the key from the DID Document that the token header's kid points to.
        try await JWSSignerVerifier.verify(jws: jws, kid: kid)

        // sub must exactly match the uri the credential points to — prevents splicing in a token from a
        // different list.
        guard decoded.payload["sub"] as? String == uri else {
            throw StatusListError.subjectMismatch
        }
        try validateLifetime(decoded.payload)

        return try decodedList(payload: decoded.payload)
    }

    /// Reads one slot at the index from the decompressed status array and converts it to a status.
    private static func status(in list: VerifiedList, index: Int) throws -> StatusListStatus {
        let value = try statusValue(list: list, index: index)
        guard let status = StatusListStatus(rawValue: value) else {
            throw StatusListError.invalidStatusList
        }
        guard status != .reserved else {
            throw StatusListError.reservedStatus
        }
        return status
    }

    // MARK: - payload verification · bit extraction

    /// Checks `exp`/`iat`. Expired tokens are rejected — signatures stay valid forever, so an old token issued
    /// before a revocation took effect cannot be filtered out by signature alone. (`ttl` is for cache cadence and is ignored.)
    private static func validateLifetime(_ payload: [String: Any]) throws {
        let now = Date()
        if let exp = (payload["exp"] as? NSNumber)?.doubleValue,
           Date(timeIntervalSince1970: exp) < now {
            throw StatusListError.tokenExpired
        }
        // Allow up to 1 minute of future issuance to tolerate device clock skew.
        if let iat = (payload["iat"] as? NSNumber)?.doubleValue,
           Date(timeIntervalSince1970: iat) > now.addingTimeInterval(60) {
            throw StatusListError.tokenExpired
        }
    }

    /// Upper bound on decompressed size — generous relative to the default capacity (100k entries × 2bit = 25KB), but blocks zip bombs.
    private static let maxDecompressedBytes = 1 << 20   // 1 MiB

    /// payload `status_list` → decompressed status array.
    private static func decodedList(payload: [String: Any]) throws -> VerifiedList {
        guard let statusList = payload["status_list"] as? [String: Any],
              let bits = (statusList["bits"] as? NSNumber)?.intValue,
              [1, 2, 4, 8].contains(bits),
              let lst = statusList["lst"] as? String,
              let compressed = base64URLDecoded(lst)
        else {
            throw StatusListError.invalidStatusList
        }
        return VerifiedList(bytes: try inflate(compressed), bits: bits)
    }

    /// Status integer at position `idx`. Statuses are stored from the LSB within each byte.
    private static func statusValue(list: VerifiedList, index: Int) throws -> Int {
        let bitIndex = index * list.bits
        let byteIndex = bitIndex / 8
        guard index >= 0, byteIndex < list.bytes.count else {
            throw StatusListError.invalidStatusList
        }
        let shift = bitIndex % 8
        let mask = (1 << list.bits) - 1
        return (Int(list.bytes[list.bytes.startIndex + byteIndex]) >> shift) & mask
    }

    /// ZLIB (RFC 1950) decompression. Apple's `.zlib` algorithm is, despite its name, raw DEFLATE (RFC 1951), so
    /// the 2-byte header and 4-byte adler32 trailer are stripped before passing it in.
    private static func inflate(_ data: Data) throws -> Data {
        guard data.count > 6 else { throw StatusListError.invalidStatusList }
        let cmf = data[data.startIndex]
        let flg = data[data.startIndex + 1]
        // CM=8 (deflate), header checksum, no preset dictionary.
        guard cmf & 0x0F == 8,
              (UInt16(cmf) << 8 | UInt16(flg)) % 31 == 0,
              flg & 0x20 == 0
        else {
            throw StatusListError.invalidStatusList
        }

        let deflate = Data(data.dropFirst(2).dropLast(4))
        guard let inflated = try? (deflate as NSData).decompressed(using: .zlib) as Data,
              inflated.count <= maxDecompressedBytes
        else {
            throw StatusListError.invalidStatusList
        }
        return inflated
    }

    /// base64url → Data. Restores notation with omitted padding (`=`) to standard base64 before decoding.
    private static func base64URLDecoded(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}
