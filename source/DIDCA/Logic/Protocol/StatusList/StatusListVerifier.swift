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

/// Status List 상태값 (`draft-ietf-oauth-status-list-21`, 서버 기본 설정 bits=2).
enum StatusListStatus: Int {
    case valid = 0
    case invalid = 1
    case suspended = 2
    /// 예약값. 서버는 사용하지 않으며, 마주치면 유효로 취급하지 않는다.
    case reserved = 3
}

enum StatusListError: Error {
    /// status 참조가 형식에 맞지 않음 (uri 없음 / idx 가 0 이상 정수가 아님).
    case invalidReference
    /// 조회 주소가 http·https 가 아님.
    case unsupportedURIScheme
    /// Status List Token 조회가 비-2xx.
    case fetchFailed(Int)
    /// 응답이 compact JWS 가 아니거나 헤더가 규격과 다름 (typ ≠ statuslist+jwt / alg ≠ ES256 / kid 없음).
    case invalidToken
    // 서명자 신원 확인 실패는 `JWSSignerError` 로 그대로 전파된다 — kid 규약 위반·서명 키 미발견·
    // 서명 불일치. 이 흐름 전용 오류가 아니라 JWS 를 kid 로 검증하는 모든 곳이 같은 것을 던진다.
    /// payload 의 sub 가 크리덴셜이 가리키는 uri 와 다름.
    case subjectMismatch
    /// 토큰이 만료됐거나 발급 시각이 미래.
    case tokenExpired
    /// status_list 구조가 규격에 맞지 않음 (bits 허용값 밖 / lst 디코딩·압축 해제 실패 / idx 범위 밖).
    case invalidStatusList
    /// RESERVED(3) — 유효한 크리덴셜로 처리하지 않는다.
    case reservedStatus
}

// MARK: - Status List Token 검증 (IETF Token Status List)
//
// 연동 가이드("Status List 클라이언트 연동 가이드", draft-ietf-oauth-status-list-21 기준) §3·§4.
// 크리덴셜이 가리키는 `status.status_list.{uri, idx}` 로 공개 Status List Token 을 받아 서명을
// 검증하고, 해당 인덱스의 상태 비트만 읽어 돌려준다. SD-JWT·mDoc 둘 다 같은 규격이라 이 한 경로를
// 공유한다 — 참조는 SDK 가 포맷별로 읽어 `StatusListReference` 로 준다.
//
//   [1] status(for:)       GET uri → JWS 검증 → sub/exp/iat 확인 → lst 해제 → idx 비트 추출
//   [2] statuses(for:)     같은 uri 를 가리키는 여러 건은 토큰을 한 번만 받아 인덱스별로 읽는다
//
// **결과는 상태 enum 한 개만 돌려준다** — 토큰 원문도, 압축 해제한 상태 배열도 보관하지 않는다.
// 조회 실패·검증 실패는 삼키지 않고 throw 한다. 호출측(CredentialStore)이 "유효"로 대체하지 않고
// 만료일 기준 표시 + 안내로 처리한다 (가이드 §5 — 실패를 VALID 로 처리 금지).
nonisolated enum StatusListVerifier {

    /// 크리덴셜이 가리키는 Status List 위치 — SDK 가 SD-JWT·mDoc 양쪽에서 같은 타입으로 준다.
    /// 앱이 payload·MSO 를 직접 뒤져 만들지 않는다(`SdJwtCredentialItem.status` / `MdocCredentialItem.status`).
    typealias Reference = StatusListReference

    /// 상태 조회 — 토큰을 받아 검증하고 해당 인덱스의 상태를 돌려준다.
    /// 조회는 항상 서버까지 간다 (HTTP 캐시를 쓰지 않는다).
    static func status(for reference: Reference) async throws -> StatusListStatus {
        let list = try await verifiedList(uri: reference.uri)
        return try Self.status(in: list, index: reference.idx)
    }

    /// 여러 크리덴셜의 상태를 한 번에 판정한다 — **같은 uri 를 가리키는 항목은 토큰을 한 번만**
    /// 받아 검증하고 인덱스별 비트만 읽는다(지갑의 SD-JWT 가 대개 같은 리스트를 공유한다).
    /// 검증한 토큰과 압축 해제한 배열은 이 호출이 끝나면 버려지고, 호출측에는 상태 enum 만 남는다.
    /// 개별 실패는 다른 크리덴셜 판정을 막지 않도록 항목별 `Result` 로 돌려준다.
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

    /// 검증까지 마친 상태 배열 — 압축 해제된 바이트와 entry 당 비트 수.
    private struct VerifiedList {
        let bytes: Data
        let bits: Int
    }

    /// 토큰 조회 → 헤더·서명·`sub`·수명 검증 → `lst` 해제. 인덱스 해석은 하지 않는다.
    private static func verifiedList(uri: String) async throws -> VerifiedList {
        guard let url = URL(string: uri),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            throw StatusListError.unsupportedURIScheme
        }

        // 서버가 `Cache-Control: max-age=300` 을 주지만 이 토큰은 캐시하지 않는다 — 낡은 값은
        // 폐기·정지 반영을 최대 5분 늦춘다. SDK `CommunicationClient` 가 전용 ephemeral 세션
        // (urlCache 없음 + `reloadIgnoringLocalCacheData`)으로만 내보내므로 그걸 그대로 쓴다.
        // 기본 헤더에는 GET 에 맞지 않는 `Content-Type: application/json` 이 있어 Accept 만 넘긴다.
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

        // 세그먼트 원문(서명 입력)은 SDK JWS 로, header/payload 해석은 SimpleJWTDecoder 로 얻는다.
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

        // 발급자 신원 확인 — 토큰 헤더의 kid 가 가리키는 DID Document 의 키로 검증한다.
        try await JWSSignerVerifier.verify(jws: jws, kid: kid)

        // sub 는 크리덴셜이 가리키는 uri 와 정확히 일치해야 한다 — 다른 리스트의 토큰을 붙여
        // 넣는 것을 막는다.
        guard decoded.payload["sub"] as? String == uri else {
            throw StatusListError.subjectMismatch
        }
        try validateLifetime(decoded.payload)

        return try decodedList(payload: decoded.payload)
    }

    /// 해제된 상태 배열에서 인덱스 한 자리를 읽어 상태로 변환.
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

    // MARK: - payload 검증 · 비트 추출

    /// `exp`/`iat` 확인. 만료된 토큰은 거부한다 — 서명은 영구히 유효하므로, 폐기 반영 전에 발행된
    /// 옛 토큰이 그대로 돌아오면 서명만으로는 걸러지지 않는다. (`ttl` 은 캐시 주기용이라 보지 않는다.)
    private static func validateLifetime(_ payload: [String: Any]) throws {
        let now = Date()
        if let exp = (payload["exp"] as? NSNumber)?.doubleValue,
           Date(timeIntervalSince1970: exp) < now {
            throw StatusListError.tokenExpired
        }
        // 기기 시계 오차를 감안해 미래 발급은 1분까지 허용.
        if let iat = (payload["iat"] as? NSNumber)?.doubleValue,
           Date(timeIntervalSince1970: iat) > now.addingTimeInterval(60) {
            throw StatusListError.tokenExpired
        }
    }

    /// 압축 해제 결과 상한 — 기본 용량(10만 엔트리 × 2bit = 25KB) 대비 넉넉하되, 압축 폭탄은 막는다.
    private static let maxDecompressedBytes = 1 << 20   // 1 MiB

    /// payload 의 `status_list` → 해제된 상태 배열.
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

    /// `idx` 위치의 상태 정수. 상태는 byte 안에서 LSB 부터 저장된다.
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

    /// ZLIB(RFC 1950) 해제. Apple 의 `.zlib` 알고리즘은 이름과 달리 raw DEFLATE(RFC 1951) 이므로
    /// 2바이트 헤더와 4바이트 adler32 트레일러를 벗겨서 넘긴다.
    private static func inflate(_ data: Data) throws -> Data {
        guard data.count > 6 else { throw StatusListError.invalidStatusList }
        let cmf = data[data.startIndex]
        let flg = data[data.startIndex + 1]
        // CM=8(deflate), 헤더 체크섬, preset dictionary 미사용.
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

    /// base64url → Data. 패딩(`=`)이 생략된 표기를 표준 base64 로 복원해 디코딩한다.
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
