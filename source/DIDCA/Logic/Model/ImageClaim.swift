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

/// 이미지 클레임(portrait 등) 판정과 값 디코드 — 설계서 VC-B-01 / VC-B-03.
///
/// **판정 기준은 포맷마다 다르다.**
/// - SD-JWT / mDoc: 클레임 **이름 화이트리스트**만 본다. 발급 메타의 타입 정보를 믿을 수 없는 포맷이다.
/// - W3C(OpenDID) VC: 데이터 모델에 실려 오는 `claim.type` 을 그대로 쓴다. 이름 추측보다 정확하고,
///   화이트리스트 밖 이름으로 발급된 기존 이미지 클레임이 텍스트로 퇴행하지 않는다.
///   (설계서 문구는 "이름 화이트리스트로만 판정"이지만 그건 안드로이드/EUDI mDoc 기준 — iOS 는
///   포맷별로 나눈다. 사용자 결정 2026-08-11.)
///
/// 판정이 갈려도 **값 디코드 규칙은 공통**이고, 어느 경우에도 오류 다이얼로그는 띄우지 않는다
/// (빈 선택 항목은 정상 상태다). 폴백 표시는 무엇이 남아 있느냐에 따라 갈린다 — 이름 판정(SD-JWT)은
/// 원문 텍스트가 그대로 값이므로 원문, mDoc 은 바이트열뿐이라 `"(N bytes)"`, 타입 판정(W3C)에서
/// 이미지로 선언됐는데 안 열리면 원문이 수 KB base64 라 쓰지 않고 `"—"` 로 둔다.
/// 상태 없는 순수 변환이라 `nonisolated` 다 — 프로토콜 계층(`OID4VPPresenter` 등)이 메인 액터
/// 밖에서 카드 목록을 만들면서 호출한다.
nonisolated enum ImageClaim {

    /// 이미지로 그릴 클레임 이름. EUDI 레퍼런스 지갑과 같은 목록이다.
    private static let imageNames: Set<String> = ["portrait", "picture", "signature_usual_mark"]

    /// 이름이 화이트리스트에 드는가 — **마지막 `.` 뒤 세그먼트**로만 비교한다.
    /// 발급자가 네임스페이스를 붙여 보내도(`eu.europa.ec.eudi.pid.1.portrait`) 같게 인식한다.
    static func isImageName(_ claimName: String) -> Bool {
        let segment = claimName.split(separator: ".").last.map(String.init) ?? claimName
        return imageNames.contains(segment.lowercased())
    }

    /// SD-JWT · mDoc 클레임 한 건의 표시값 — 이름이 화이트리스트에 들고 값이 이미지로 읽히면
    /// `.image`, 그 외에는 `.text`(원문 그대로).
    static func claimValue(name: String, text: String) -> ClaimValue {
        guard isImageName(name), let data = decode(text) else { return .text(text) }
        return .image(data)
    }

    /// mDoc 원소 한 건의 표시값 — 값이 이미 바이트열이라 디코드할 것이 없다.
    ///
    /// 이미지로 열리지 않으면 `"(N bytes)"` 로 적는다(설계서 VC-B-01). SD-JWT·W3C 의 폴백은 "원문
    /// 텍스트"지만 여기엔 원문 텍스트가 없다 — 바이트열을 문자열로 흉내 내면 깨진 글자만 남는다.
    static func claimValue(name: String, data: Data) -> ClaimValue {
        guard isImageName(name), !data.isEmpty, UIImage(data: data) != nil else {
            return .text("(\(data.count) bytes)")
        }
        return .image(data)
    }

    /// W3C(OpenDID) VC 클레임 한 건의 표시값 — 판정은 `claim.type`.
    ///
    /// 이미지가 아닌 클레임은 원문 텍스트가 곧 표시값이다. 반면 **이미지로 선언됐는데 열리지 않으면
    /// 원문을 쓰지 않는다** — 그 원문은 수 KB base64 라서 라벨 자리에 통째로 쏟아진다. 사람이 읽을
    /// 값이 아니므로 빈 값 표시로 물러난다(`claimValue(name:data:)` 의 `"(N bytes)"` 와 같은 취지).
    static func claimValue(type: ClaimType, encoded: String) -> ClaimValue {
        guard type == .image else { return .text(encoded) }
        guard let data = decode(encoded) else { return .text(unreadableImageText) }
        return .image(data)
    }

    /// 이미지로 선언된 클레임이 이미지로 열리지 않을 때의 표시값.
    private static let unreadableImageText = "—"

    /// 인코딩된 값 → 이미지 `Data`. 이미지로 읽히지 않으면 nil.
    ///
    /// 허용 형식: `data:` URI 접두가 붙은 base64, 표준·URL-safe base64, multibase.
    /// 디코드에 성공해도 **실제로 이미지로 열리는지**(`UIImage`)까지 확인한다 — 임의 문자열도
    /// base64 로는 곧잘 디코드되므로, 이 확인이 없으면 텍스트가 빈 이미지 칸으로 둔갑한다.
    static func decode(_ encoded: String) -> Data? {
        let payload = strippingDataURIPrefix(encoded)
        guard !payload.isEmpty else { return nil }   // 빈 값은 정상 상태 — 폴백 대상이다.

        let decoded = base64Decoded(payload) ?? (try? MultibaseUtils.decode(encoded: payload))
        guard let decoded, !decoded.isEmpty, UIImage(data: decoded) != nil else { return nil }
        return decoded
    }

    /// `data:image/png;base64,` 같은 접두를 떼고 payload 만 남긴다. 접두가 없으면 원문 그대로.
    private static func strippingDataURIPrefix(_ value: String) -> String {
        guard value.hasPrefix("data:"), let comma = value.firstIndex(of: ",") else { return value }
        return String(value[value.index(after: comma)...])
    }

    /// 표준 base64 로 먼저, 실패하면 URL-safe(`-`/`_`) 를 표준으로 되돌려 한 번 더 시도한다.
    /// 패딩(`=`)이 생략된 표기도 복원한다.
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
