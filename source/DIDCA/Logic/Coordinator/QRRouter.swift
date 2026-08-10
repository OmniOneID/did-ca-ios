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

/// 스캔을 시작한 진입점이 기대하는 흐름.
///
/// 같은 스캐너 화면을 + 버튼(발급)과 Present 버튼(제출)이 공유하는데, QR 자체는 두 흐름을 모두
/// 담을 수 있다. 진입 버튼이 이미 의도를 말했으므로 그와 다른 QR 은 받지 않는다 — 사용자가
/// "추가"를 눌렀는데 제출 화면이 뜨는 일이 없게 한다.
enum ScanIntent {
    /// + → Scan QR. 발급 QR 만 받는다.
    case issue
    /// Present → Scan QR. 제시 QR 만 받는다.
    case present
    /// 딥링크 — 진입 버튼이 없어 흐름을 한정할 근거가 없다. 둘 다 받는다.
    case any

    /// 스캔된 QR 의 흐름을 이 진입점이 받아도 되는지.
    func accepts(_ flow: ScanIntent) -> Bool { self == .any || self == flow }
}

// 스캔·딥링크로 들어온 페이로드를 종류별 발급/제시 흐름으로 흘리는 라우터.
//
// 화면 스택·모달·사용자 입력 상태는 전부 AppCoordinator 소유라 그 인스턴스를 인자로 받아
// 위임한다 — 이 타입이 아는 것은 "어떤 페이로드를 어떤 프로토콜에 어떤 순서로 태울지" 뿐이고,
// 상태를 따로 들지 않는다(그래서 enum 네임스페이스 + static). 진입점은 두 개다:
//   handle(_:on:)                   QR 스캔 / 딥링크 (오퍼가 흐름의 출발점)
//   startOID4VciWebIssuance(...)    목록에서 고른 뒤 WebView 를 거쳐 오퍼를 받아오는 발급
enum QRRouter {

    /// 스캔 문자열의 종류 — scheme prefix 로 판별.
    private enum ScannedQRKind { case oid4vp, oid4vci, openDID }

    /// 스캔된 QR 처리 — scheme 으로 OID4VP / OID4VCI / OpenDID 를 가른다.
    ///
    /// `intent` 는 스캔을 시작한 진입점이 기대하는 흐름이다. 종류가 어긋나면 흐름을 시작하지 않고
    /// 안내만 한다 — 서버 호출·인증·화면 전환이 시작되기 **전에** 걸러야 사용자가 엉뚱한 흐름
    /// 중간에서 되돌아 나오는 일이 없다.
    static func handle(_ qrString: String,
                       intent: ScanIntent = .any,
                       on coordinator: AppCoordinator) async {
        switch classify(qrString) {
        case .oid4vp:
            guard intent.accepts(.present) else { return reject(intent) }
            await handleOID4VP(qrString, on: coordinator)
        case .oid4vci:
            guard intent.accepts(.issue) else { return reject(intent) }
            await handleOID4VCI(qrString, on: coordinator)
        case .openDID:
            // OpenDID 는 scheme 으로 발급/제시를 알 수 없다 — payloadType 을 읽은 뒤 판정한다.
            await handleOpenDID(qrString, intent: intent, on: coordinator)
        }
    }

    /// 진입 버튼과 다른 종류의 QR — 어디로 가야 하는지 알려준다.
    /// `.any`(딥링크)는 제한이 없어 이 경로로 오지 않는다.
    private static func reject(_ intent: ScanIntent) {
        let message: String
        switch intent {
        case .issue:
            message = "This QR code is for presenting a credential. Use Present to submit one."
        case .present:
            message = "This QR code is for issuing a credential. Use + to add one."
        case .any:
            return
        }
        OverlayManager.shared.showPopup(title: "Unexpected QR code",
                                        message: message,
                                        primaryButtonTitle: "OK")
    }

    /// OpenDID 페이로드는 URL scheme 이 아니라 multibase 문자열이라 `openid*` prefix 와
    /// 절대 겹치지 않는다 → 두 scheme 을 먼저 보고 나머지를 OpenDID 로 흘린다.
    private static func classify(_ qr: String) -> ScannedQRKind {
        if qr.hasPrefix("openid4vp") { return .oid4vp }
        if qr.hasPrefix("openid-credential-offer") { return .oid4vci }
        return .openDID
    }

    /// 기존 OpenDID 처리 — payloadType 으로 발급/제시를 가른다.
    /// 흐름이 payload 안에 있으므로 `intent` 대조도 디코딩 뒤에 한다.
    private static func handleOpenDID(_ qrString: String,
                                      intent: ScanIntent,
                                      on coordinator: AppCoordinator) async {
        do {
            let dataPayload = try DataPayload(from: qrString)
            let data = try MultibaseUtils.decode(encoded: dataPayload.payload)
            if dataPayload.payloadType == "ISSUE_VC" {
                guard intent.accepts(.issue) else { return reject(intent) }
                await issueFromQR(data: data, on: coordinator)
            } else {
                guard intent.accepts(.present) else { return reject(intent) }
                await presentFromQR(data: data, on: coordinator)
            }
        } catch {
            OverlayManager.shared.showErrorPopup(title: "Invalid QR code", error: error)
        }
    }

    /// OID4VP 제시 — `openid4vp://...?request_uri=` 인가요청을 파싱하고, DCQL 매칭으로
    /// 제출 가능한 VC 가 있으면 VPRequestView(.oid4vpRequest)를 띄운다. 매칭 VC 가 없거나
    /// 파싱/검증 실패 시 오류 팝업. 실제 제출은 submitOID4VP 가 담당 (일반 VP 와 평행 구조).
    private static func handleOID4VP(_ qrString: String, on coordinator: AppCoordinator) async {
        OverlayManager.shared.showLoading()
        defer { OverlayManager.shared.hideLoading() }
        do {
            let authRequest = try await OID4VPPresenter.getAuthorizationRequest(uri: qrString)
            coordinator.oid4vpRequest = authRequest
            // 일반 VP 와 달리 summary 는 제출 가능 여부 판정(matchCredentials)도 겸한다 —
            // 실패(noMatchedCredentials 등)면 제시 자체가 불가하므로 try 로 전파해 오류 팝업.
            coordinator.oid4vpSummary = try await OID4VPPresenter.presentationSummary(authRequest: authRequest)
            coordinator.push(.oid4vpRequest)
        } catch {
            OverlayManager.shared.showErrorPopup(title: "Failed to load presentation", error: error)
        }
    }

    /// OID4VCI 발급 — `openid-credential-offer://...?credential_offer_uri=` 를 `IssueOID4VcProtocol`
    /// 로 처리한다. SDK 흐름(getCredentialOffer → getMetadata → getToken → requestCredential)은
    /// 프로토콜이 담당하고, 여기서는 그 사이에 끼는 UI(로딩·grant type 팝업·tx_code 모달·holder
    /// 인증 시트·성공 화면)만 오케스트레이션한다. requestCredential 이 발급 VC 저장까지 처리하므로
    /// 발급 후 reload 하면 지갑 목록에 새 카드가 반영된다.
    ///
    /// - parameter expecting: 목록 기반(WebView) 발급에서만 채워진다 — 사용자가 고른 Issuer·
    ///   Credential 과 돌아온 오퍼가 같은지 대조한다(가이드 §8). QR·딥링크 발급은 오퍼가 흐름의
    ///   출발점이라 대조할 기준값이 없어 nil.
    private static func handleOID4VCI(_ qrString: String,
                                      expecting: OID4VciExpectation? = nil,
                                      on coordinator: AppCoordinator) async {
        do {
            OverlayManager.shared.showLoading()
            let issue = try await IssueOID4VcProtocol.begin(rawPayload: qrString)

            if let expecting {
                try issue.validate(expectedIssuer: expecting.issuer,
                                   configurationId: expecting.configurationId)
            }

            // v1 은 pre-authorized_code 만 지원.
            guard issue.isPreAuthorized else {
                OverlayManager.shared.hideLoading()
                OverlayManager.shared.showPopup(
                    title: "Notification",
                    message: "This issuance type is not supported yet.",
                    primaryButtonTitle: "OK"
                )
                return
            }
            OverlayManager.shared.hideLoading()

            // tx_code 가 offer 에 명시된 경우에만 입력 모달 — length/description 은 offer 메타 주입.
            // 요구하지 않으면 nil 로 둔다(빈 문자열을 넘기면 token 요청에 `tx_code=` 가 실린다).
            // WebView 발급은 서버가 tx_code 없는 Pre-Authorized Code 를 만들어 항상 이 경로다.
            let pinCode: String?
            if let txCode = issue.txCode {
                // tx_code 는 numeric 만 지원 (숫자 패드 입력). input_mode 미지정은 OID4VCI 기본값 numeric 으로 본다.
                // text 등 비-numeric 모드면 입력 수단이 없어 발급을 중단한다 (서버 계약상 numeric-only).
                if let mode = txCode.inputMode, mode.lowercased() != "numeric" {
                    OverlayManager.shared.showPopup(
                        title: "Notification",
                        message: "This issuance requires a non-numeric code, which isn't supported.",
                        primaryButtonTitle: "OK"
                    )
                    return
                }
                guard let entered = await coordinator.presentTxCode(
                    length: txCode.length ?? 6,
                    description: txCode.description ?? ""
                ) else { return }
                pinCode = entered
            } else {
                pinCode = nil
            }

            // holder 키 인증 — bio 키가 없으면 PIN 직행, 있으면 인증수단 선택 시트가 뜬다.
            // 선택 결과(passcode)가 발급 proof 서명 키를 정한다: PIN→#pin 키, BIO→#bio 키
            // (SDK requestCredential 이 password != nil ? "pin" : "bio"). tx_code(issuer 거래코드)와
            // 별개인 holder 본인확인 단계다.
            guard let auth = await coordinator.presentAuth() else { return }

            OverlayManager.shared.showLoading()
            defer { OverlayManager.shared.hideLoading() }

            // 반환값은 지갑에 저장된 SD-JWT 의 id — 재로딩한 목록에서 이 id 로 카드를 찾아
            // 제목을 정한다(목록·상세와 같은 이름). SD-JWT 저장소는 W3C 와 분리돼 있지만
            // loadCredentials 가 둘을 합쳐 읽으므로 새 카드가 그대로 반영된다.
            let credentialId = try await issue.process(txCode: pinCode, passcode: auth.passcode)
            await coordinator.completeIssuance(vcId: credentialId)
        } catch {
            coordinator.failIssuance(error)
        }
    }

    // MARK: - OID4VCI 목록 기반(user-initiated) 발급
    //
    // QR 발급이 오퍼에서 시작하는 것과 달리, 여기서는 사용자가 목록에서 Issuer·Credential 을
    // 먼저 고르고 Issuer 의 클레임 입력 WebView 를 거쳐 오퍼를 받아온다. 오퍼를 받은 뒤로는
    // QR 발급과 **같은 경로**(handleOID4VCI)로 합류한다 — WebView 전용 Token/Credential Request 는 없다.

    /// 목록에서 고른 Issuer 와 Credential — 완료 오퍼 대조 기준값 (가이드 §8).
    struct OID4VciExpectation {
        let issuer: String
        let configurationId: String
    }

    /// Credential 선택 → 클레임 입력 WebView → 완료 오퍼로 기존 발급 경로 진입.
    /// WebView 를 닫거나 서버 화면에서 Cancel 하면 아무것도 발급되지 않고 선택 화면에 머문다.
    ///
    /// 선택한 카드가 속한 Issuer 와 그 metadata 를 화면에서 그대로 받는다 — 한 화면에 여러 Issuer 가
    /// 섹션으로 놓이므로 "현재 선택된 Issuer" 를 코디네이터가 들고 있지 않는다.
    static func startOID4VciWebIssuance(issuer: OID4VCIIssuerItem,
                                        metadata: IssuerMetadataResponse,
                                        configurationId: String,
                                        on coordinator: AppCoordinator) async {
        guard let userInitiationUri = issuer.userInitiationUri else { return }

        let startURL: URL
        do {
            startURL = try OID4VciIssuerDirectory.startURL(
                userInitiationUri: userInitiationUri,
                configurationId: configurationId,
                did: WalletState.holderDID,
                userName: WalletState.userName,
                metadata: metadata
            )
        } catch {
            OverlayManager.shared.showErrorPopup(title: "Failed to start issuance", error: error)
            return
        }

        // 이후 navigation 은 시작 URL 의 host 안에서만 허용한다 (가이드 §11).
        guard let allowedHost = startURL.host else {
            OverlayManager.shared.showErrorPopup(
                title: "Failed to start issuance",
                error: OID4VciDirectoryError.invalidStartURL
            )
            return
        }

        // 닫기·취소면 nil — 로컬 상태만 취소로 두고 조용히 화면에 머문다.
        guard let completion = await coordinator.presentOID4VciWebView(url: startURL, allowedHost: allowedHost) else {
            return
        }

        await handleOID4VCI(
            completion,
            expecting: OID4VciExpectation(
                issuer: OID4VciIssuerDirectory.expectedIssuer(
                    listed: issuer.credentialIssuer,
                    metadata: metadata
                ),
                configurationId: configurationId
            ),
            on: coordinator
        )
    }

    // MARK: - OpenDID 페이로드 분기

    /// QR 발급 — IssueOfferPayload → 인증 → 발급 핸드셰이크 → 성공 화면.
    private static func issueFromQR(data: Data, on coordinator: AppCoordinator) async {
        do {
            let offer = try IssueOfferPayload(from: data)
            print("▶️[QR-ISSUE]◀️ offer.vcPlanId=\(offer.vcPlanId) issuer=\(offer.issuer) offerId=\(offer.offerId ?? "nil") type=\(offer.type)")
            guard let auth = await coordinator.presentAuth() else { return }

            OverlayManager.shared.showLoading()
            defer { OverlayManager.shared.hideLoading() }
            let vcId = try await IssueVcProtocol.issue(offer: offer, passcode: auth.passcode)
            await coordinator.completeIssuance(vcId: vcId)
        } catch {
            coordinator.failIssuance(error)
        }
    }

    /// QR 제시 — VerifyOfferPayload.type 으로 일반 VP / ZKP VP 분기.
    private static func presentFromQR(data: Data, on coordinator: AppCoordinator) async {
        OverlayManager.shared.showLoading()
        defer { OverlayManager.shared.hideLoading() }
        do {
            let offer = try VerifyOfferPayload(from: data)
            print("▶️[QR-VP]◀️ offer.type=\(offer.type) offerId=\(offer.offerId) mode=\(offer.mode) endpoints=\(offer.endpoints)")
            // did-ca-ios VerifyProfileViewController.viewDidLoad 와 동일 — .VerifyOffer
            // 만 일반 VP, 그 외(.VerifyProofOffer 등) 는 모두 ZKP 경로.
            if offer.type == .VerifyOffer {
                let profile = try await VerifyVcProtocol.requestProfile(offerId: offer.offerId)
                coordinator.verifyProfile = profile
                // 표시 데이터이자 제출 계획. 제출 프로파일 규칙을 적용하는 유일한 지점이라
                // submit 은 이 결과를 그대로 쓴다. 제출 가능한 카드가 없거나 프로파일이 보유 VC 와
                // 어긋나면 throw 한다 — try? 로 삼키면 문서 0개의 빈·제출불가 화면이 뜨므로,
                // 실패는 그대로 던져 에러 팝업으로 안내하고 화면 진입 자체를 막는다.
                coordinator.verifySummary = try await VerifyVcProtocol.presentationSummary(profile: profile)
                coordinator.push(.vpRequest)
            } else {
                let proto = VerifyZKProofProtocol()
                _ = try await proto.preProcess(offerId: offer.offerId)
                coordinator.zkpProto = proto
                coordinator.zkpAttrSelections = [:]
                coordinator.zkpReveals = []
                coordinator.zkpSelfRaws = [:]
                coordinator.push(.vpRequestZkp)
            }
        } catch {
            OverlayManager.shared.showErrorPopup(title: "Failed to load presentation", error: error)
        }
    }
}
