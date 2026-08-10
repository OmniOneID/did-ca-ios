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
import DIDWalletSDK

/// 최상위 단계 — 스택에 쌓이지 않고 통째로 교체된다. 셋 사이엔 "뒤로" 개념이 없다.
enum Root: Hashable {
    case splash
    case onboarding(step: StepEnum)
    case main
}

/// 메인 위에 push 되는 화면 — `NavigationStack` 의 path 요소다.
/// 여기 있는 화면은 전부 상단이 `←` 다. `X` 로 닫는 화면은 스택이 아니라 `AppModal` 로 간다.
enum Screen: Hashable {
    /// 발급 프로토콜 선택 (화면설계서 18a) — "From list" 진입 시 Open DID / OID4VCI 를 고른다.
    /// Open DID → addCertificate(현행 플랜 리스트), OID4VCI → oid4vciIssuerList.
    case protocolSelect
    case addCertificate
    /// OID4VCI 발급 — 목록사업자의 Issuer 를 섹션으로 펼친 credential 선택 화면.
    /// Issuer 선택 단계는 따로 두지 않는다(화면 자체가 Issuer 별 섹션).
    case oid4vciCredentialSelect
    case issueSuccess
    case proximity
    case vpRequest
    /// OID4VP 제시 — 일반 VP 와 화면(VPRequestView)은 같고 제출 경로만 다르다.
    case oid4vpRequest
    case vpRequestZkp
    case citizenshipSelect
    /// ZKP attribute picker — referent key 인자로 받아 해당 속성의 후보 값 리스트를 보여줌.
    case zkpAttrSelect(key: String)
    case vcDetail(Credential)
    case menu
}

enum AppModal: Hashable {
    case pinRegister
    case pinLockRegister
    case pinChange(isLockAuth: Bool = false)
    case pinAuth(isLockAuth: Bool = false)
    case biometric(fromSettings: Bool)
    case authSelection
    // 발급 추가정보 입력 웹 폼 (DEMO_URL/addVcInfo). 연결 URL 을 동봉.
    case issueWebForm(URL)
    // OID4VCI 사용자 클레임 입력 WebView (Issuer user initiation). 시작 URL 과 허용 host 를 동봉.
    case oid4vciWebView(url: URL, allowedHost: String)
    // QR 스캔 모달 — 발급/제시 공용.
    case qrScan
    // OID4VCI tx_code 입력 모달 — pre-authorized_code 발급에서 offer 가 tx_code 를 요구할 때 표시.
    // length/description 은 offer 의 tx_code 메타에서 주입. PIN 인증(pinAuth)과 무관한 별개 입력.
    case txCode(length: Int, description: String)
    // Unlock PIN 인증 모달 — Splash 직후 / scenePhase background→active 진입 시 isLock()==true 면 표시.
    // X 버튼·시스템 백·swipe-down 모두 exit(0) (UNLK-A-E-02). pinAuth(isLockAuth:true) 와는
    // X 동작이 다르므로 별도 케이스로 분리.
    case lockAuth
}

enum BiometricResult {
    case enabled
    case skipped
}

@Observable
final class AppCoordinator {
    var root: Root = .splash
    /// 메인 위에 쌓인 화면 스택. `NavigationStack(path:)` 에 그대로 바인딩되므로,
    /// 시스템 뒤로가기(엣지 스와이프)로 사용자가 직접 줄일 수도 있다.
    var path: [Screen] = []
    var modal: AppModal? = nil
    /// 위에 한 겹 더 얹는 모달 — 현재 모달을 **살려 둔 채** 그 위에 띄워야 할 때만 쓴다
    /// (설정의 Add Biometrics: 바이오 화면 위로 PIN 이 올라오고, PIN 을 닫으면 바이오로 돌아간다).
    /// 잠금(lockAuth)은 항상 최상위여야 하므로 이 슬롯을 먼저 비우고 표시한다.
    var stackedModal: AppModal? = nil
    var credentials: [Credential] = []
    var pickedCred: Credential? = nil
    // 발급 완료 화면(IssueSuccessView)에 띄울 발급된 VC 의 title 목록.
    var issuedTitles: [String] = []
    var selectedCitizenship: CitizenshipOption? = nil
    // 일반 VP 제출 — QR 제시 스캔 시 requestProfile 로 받은 verifier 프로필.
    var verifyProfile: _RequestProfile? = nil
    // VPRequestView 표시용 데이터 (검증자명·제출 클레임). presentFromQR 에서 채움.
    var verifySummary: VpPresentationSummary? = nil
    // OID4VP 제출 — getAuthorizationRequest 로 파싱한 인가요청. handleOID4VP 에서 채우고
    // submitOID4VP 가 재사용 (createVp 의 nonce/challenge/responseUri 소스).
    var oid4vpRequest: AuthorizationRequest? = nil
    // OID4VP VPRequestView 표시용 데이터 (일반 VP 의 verifySummary 와 동일 타입 재사용).
    var oid4vpSummary: VpPresentationSummary? = nil
    // ZKP VP 제출 — `.VerifyProofOffer` 스캔 시 preProcess 까지 마친 protocol 인스턴스.
    // 화면 표시(presentationSummary) 와 submit 모두 같은 인스턴스를 재사용 (did-ca-ios
    // `VerifyZKProofProtocol.shared` 와 동등 — 단일 ZKP VP 세션의 상태 컨테이너).
    var zkpProto: VerifyZKProofProtocol? = nil
    // ZKP attribute / predicate picker 결과 — referent key → 선택된 sub-referent index.
    // did-ca-ios `ZKPSubmissionViewController.selectedIndexMap` 와 등가 (단, IndexPath 대신
    // 안정 키인 referent.key 사용). attribute 와 predicate 모두 같은 dictionary 에 보관 —
    // referent.key 가 두 섹션을 가로질러 고유.
    var zkpAttrSelections: [String: Int] = [:]
    // ZKP attribute reveal 토글 — eye-on 으로 선택된 attribute referent key 집합.
    // 화면 떠나면 사라지지 않도록 coordinator 에 보관 (did-ca-ios `attrHiddenState` 등가).
    var zkpReveals: Set<String> = []
    // ZKP self-attribute 사용자 입력 — referent key → 텍스트 입력값.
    // did-ca-ios `ZKPSubmissionViewController.selfRawMap` 등가 (Int 키 → String 키).
    var zkpSelfRaws: [String: String] = [:]

    // 값을 반환해야 하는 PIN 모달용 continuation (pinRegister / pinLockRegister 공용).
    // 호출 측에서 present...() await → AppRoot 의 PINView 콜백이 completePin 호출.
    @ObservationIgnored private var pinContinuation: CheckedContinuation<String?, Never>?

    // Biometric 모달 결과 (.enabled / .skipped) 를 호출 측에 전달.
    @ObservationIgnored private var biometricContinuation: CheckedContinuation<BiometricResult, Never>?

    // Auth 선택 시트 (PIN / BIO) 결과 — presentAuthSelection 의 내부 신호.
    // 사용자가 PIN 택하면 후속 presentPinAuth 로 체이닝, BIO 택하면 그대로 .bio 반환.
    @ObservationIgnored private var authSelectionContinuation: CheckedContinuation<AuthSelectionPick?, Never>?

    // 발급 웹 폼 결과 — true 면 업로드 완료(발급 진행), false 면 실패·취소(발급 중단).
    @ObservationIgnored private var issueWebFormContinuation: CheckedContinuation<Bool, Never>?

    // QR 스캔 결과 — 인식된 페이로드 문자열, 취소·닫기 시 nil.
    @ObservationIgnored private var qrScanContinuation: CheckedContinuation<String?, Never>?

    // OID4VCI tx_code 입력 결과 — 입력 완료 시 코드 문자열, 취소·닫기 시 nil.
    @ObservationIgnored private var txCodeContinuation: CheckedContinuation<String?, Never>?

    // OID4VCI 클레임 입력 WebView 결과 — 완료 redirect URL 문자열, 취소·닫기 시 nil.
    @ObservationIgnored private var oid4vciWebViewContinuation: CheckedContinuation<String?, Never>?

    // 완료 redirect 를 한 번만 처리하기 위한 가드 (가이드 §10 — 중복 redirect·빠른 연속 탭·
    // 화면 재생성 후 재처리 방지). 검증 실패로 WebView 를 유지할 때만 다시 열린다.
    @ObservationIgnored private var oid4vciOfferHandling = false

    // 이미 소비한 Credential Offer URI — 같은 오퍼로 두 번 발급을 태우지 않는다 (가이드 §8).
    @ObservationIgnored private var consumedOfferURIs: Set<String> = []

    // Unlock PIN 인증 완료 — 인증 성공 시 resume, X 버튼은 exit(0) 라 nil/cancel 케이스 없음.
    @ObservationIgnored private var lockAuthContinuation: CheckedContinuation<Void, Never>?

    // MARK: - 크리덴셜 목록 스냅샷

    /// 지갑 목록을 다시 읽어 화면에 반영. 상태 캐시를 비운 뒤 부르면 폐기·정지가 뱃지에 반영된다.
    func reloadCredentials() async {
        credentials = await CredentialStore.shared.loadCredentials()
    }

    /// 상세에서 새로 조회한 상태를 목록 스냅샷에도 반영 — 지갑을 다시 읽지 않고 그 카드만 갱신한다.
    /// (목록은 `loadCredentials()` 시점의 값 스냅샷이라, 저장소 캐시만 갱신해선 뱃지가 안 바뀐다.)
    func applyRefreshedStatus(_ status: CredentialStatus, for credentialId: String) {
        guard let index = credentials.firstIndex(where: { $0.id == credentialId }),
              credentials[index].status != status
        else {
            return
        }
        credentials[index] = credentials[index].with(status: status)
    }

    // MARK: - 화면 이동
    //
    // 최상위 단계 교체(setRoot)와 스택 조작(push/pop)을 분리한다. 이전 구조는 화면 하나를
    // 통째로 갈아끼웠기 때문에 "뒤로"가 실은 다른 화면으로의 점프였고, 그래서 전환 방향도
    // 시스템이 알 수 없었다. 이제 뒤로가기는 pop 이고, 엣지 스와이프도 그대로 동작한다.

    /// 최상위 단계 교체 — 스택은 비운다 (splash·온보딩·메인 사이엔 "뒤로"가 없다).
    func setRoot(_ newRoot: Root) {
        path.removeAll()
        root = newRoot
    }

    func push(_ screen: Screen) {
        path.append(screen)
    }

    /// 한 단계 뒤로. 스택이 비어 있으면(메인) 아무 일도 하지 않는다.
    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    /// 메인까지 되돌아간다 — 오류 팝업 확인 후 복귀처럼 "홈으로" 에 해당한다.
    func popToMain() {
        path.removeAll()
        if root != .main {
            root = .main
        }
    }

    /// 스택을 통째로 교체 — 발급 완료처럼 되돌아갈 이전 화면이 의미 없을 때 쓴다.
    func setStack(_ screens: [Screen]) {
        if root != .main {
            root = .main
        }
        path = screens
    }

    // MARK: - 딥링크 (openid4vp:// / openid-credential-offer://)

    // onOpenURL 로 들어온 딥링크를 ready 가 될 때까지 보관. 콜드런치(splash)·잠금 중에는
    // 처리를 미루고, 메인+모달없음 상태로 전이하면 drain 한다. 스캔 진입과 같은 게이팅.
    @ObservationIgnored private var pendingDeepLink: String?

    /// 스캔/딥링크 플로우를 시작해도 되는 상태 — 메인(스택 비어 있음) + 모달 없음.
    /// (QR 스캔이 원래 메인에서만 가능한 것과 동일한 게이팅.)
    var isReadyForScannedFlow: Bool {
        root == .main && path.isEmpty && modal == nil
    }

    /// onOpenURL 진입점 — 딥링크 URL 을 버퍼에 넣고, 이미 ready 면 즉시 처리.
    func handleDeepLink(_ url: URL) {
        pendingDeepLink = url.absoluteString
        drainPendingDeepLink()
    }

    /// 보관된 딥링크를 ready 일 때만 꺼내 스캔 디스패치로 흘린다.
    /// AppRoot 가 ready 전이 시(콜드런치 후 docs 도달·잠금 해제) 호출.
    func drainPendingDeepLink() {
        guard isReadyForScannedFlow, let link = pendingDeepLink else { return }
        pendingDeepLink = nil
        Task { await handleScannedQR(link) }
    }

    // MARK: - Holder DID 캐시

    // holder DID 캐시 — getDidDocument 는 CoreData fetch+JSON decode 라, 매 body 평가마다
    // 동기 호출하면 설정 진입에 딜레이가 생긴다. 온보딩 후 DID 는 불변이므로 한 번만 읽어 캐시.
    @ObservationIgnored private var holderDIDCache: String?

    /// 현재 holder DID 문자열 (설정화면 표시용). 미생성 시 빈 문자열.
    var holderDID: String {
        if let holderDIDCache { return holderDIDCache }
        guard let did = WalletState.holderDID else {
            return ""   // 아직 DID 미생성 — 캐시하지 않고 다음 호출에 재시도.
        }
        holderDIDCache = did
        return did
    }

    // MARK: - 모달
    //
    // 아래는 전부 같은 골격이다: present…() 가 모달을 세우고 continuation 에 매달려 await 하면,
    // AppRoot 에 뜬 화면의 콜백이 complete…() 를 불러 그 continuation 을 resume한다. 그래서
    // 호출 측은 모달을 "값을 돌려주는 함수"처럼 쓸 수 있다 (`await presentPinAuth()`).
    // 짝(present/complete)이 항상 붙어 다니므로 모달 종류별로 묶어 둔다.

    func present(_ m: AppModal) {
        modal = m
    }

    // MARK: 모달 — PIN 입력·변경

    /// PIN Lock 등록 모달. 사용자가 X 로 취소하면 nil.
    func presentPinLockRegister() async -> String? {
        await presentPinModal(.pinLockRegister)
    }

    /// PIN 등록 모달 (서명키 등록용). 사용자가 X 로 취소하면 nil.
    func presentPinRegister() async -> String? {
        await presentPinModal(.pinRegister)
    }

    /// PIN 인증 모달 (서명 등 입력값 필요한 경우 PIN 반환). 사용자가 X 로 취소하면 nil.
    /// `stacked: true` 면 현재 모달을 닫지 않고 그 위에 얹는다 — 취소 시 아래 화면으로 돌아간다.
    func presentPinAuth(isLockAuth: Bool = false, stacked: Bool = false) async -> String? {
        await presentPinModal(.pinAuth(isLockAuth: isLockAuth), stacked: stacked)
    }

    // 잠금 표시 직전의 모달 상태 — 인증 후 그대로 되돌린다. 잠금은 진행 중이던 흐름을
    // "끝내는" 게 아니라 "가리는" 것이기 때문이다.
    @ObservationIgnored private var modalBeforeLock: (modal: AppModal?, stacked: AppModal?)?

    /// Unlock PIN 인증 모달 — 인증 성공할 때만 반환. X 버튼/swipe-down 은 PINView 측에서 exit(0).
    ///
    /// 진행 중이던 모달 흐름은 **취소하지 않고 보류**한다. continuation 을 깨우지 않으면
    /// 대기 중인 태스크는 그 자리에 멈춰 있을 뿐이고, 인증 후 모달을 되돌리면 사용자가
    /// 있던 자리에서 그대로 이어진다. 예전처럼 취소로 깨우면 흐름이 "사용자가 선택했다"고
    /// 오해하고 계속 진행한다 — 온보딩 step2 라면 생체를 Skip 으로 보고 잠금화면 뒤에서
    /// 키 생성과 DID 문서 발행까지 마친 뒤 step3 로 넘어가 버린다.
    func presentLockAuth() async {
        if let prev = lockAuthContinuation {
            lockAuthContinuation = nil
            prev.resume()
        }
        // 이미 잠금이 떠 있는데 다시 불린 경우엔 보관값을 덮지 않는다 (원래 화면을 잃는다).
        if modalBeforeLock == nil {
            modalBeforeLock = (modal, stackedModal)
        }
        // 잠금화면은 보안상 즉시 콘텐츠를 덮어야 한다 — fullScreenCover 의 기본 슬라이드업
        // 모션을 억제해 모달 애니메이션 없이 바로 표시한다. 모달 슬롯은 nil 을 거치지 않고
        // 바로 잠금으로 교체한다 (중간 nil → present-while-dismissing 재표시 위험 회피).
        // 얹어 띄운 겹은 걷어낸다 — 안 그러면 잠금이 그 아래에 깔린다. 복원 때 다시 세운다.
        withTransaction(Self.noAnimation) {
            stackedModal = nil
            modal = .lockAuth
        }
        await withCheckedContinuation { cont in
            lockAuthContinuation = cont
        }
    }

    /// Unlock 인증 성공 — PINView onSuccess 콜백에서 호출.
    /// 잠금 직전에 떠 있던 모달을 되돌린다 (없었으면 nil 로 닫는 것과 같다).
    func completeLockAuth() {
        if let cont = lockAuthContinuation {
            lockAuthContinuation = nil
            cont.resume()
        }
        let restored = modalBeforeLock
        modalBeforeLock = nil
        // present 와 대칭으로 dismiss 모션도 억제 (슬라이드다운으로 콘텐츠가 잠깐 비치지 않게).
        withTransaction(Self.noAnimation) {
            modal = restored?.modal
            stackedModal = restored?.stacked
        }
    }

    /// fullScreenCover present/dismiss 모션을 끄기 위한 transaction (잠금화면 전용).
    private static var noAnimation: Transaction {
        var txn = Transaction()
        txn.disablesAnimations = true
        return txn
    }

    private func presentPinModal(_ m: AppModal, stacked: Bool = false) async -> String? {
        if let prev = pinContinuation {
            pinContinuation = nil
            prev.resume(returning: nil)
        }
        if stacked {
            stackedModal = m
        } else {
            modal = m
        }
        return await withCheckedContinuation { cont in
            pinContinuation = cont
        }
    }

    /// PIN 입력 완료 — continuation resume + 모달 닫기.
    /// resume 과 modal=nil 이 같은 프레임에 일어나 dismiss 시작과 동시에 호출 측이
    /// 재개된다 → 호출 측 로딩이 모달 슬라이드와 함께 노출 (목록이 노출되는 텀 없음).
    /// 얹어 띄운 PIN 이면 그 겹만 걷어낸다 — 아래 화면은 그대로 남는다.
    func completePin(_ pin: String) {
        if let cont = pinContinuation {
            pinContinuation = nil
            cont.resume(returning: pin)
        }
        if stackedModal != nil {
            stackedModal = nil
        } else {
            modal = nil
        }
    }

    /// PIN 변경 모달 완료 처리. isLockAuth 면 Unlock PIN 변경(changeLock),
    /// 아니면 서명 PIN 변경(changePin). 성공 시 모달 닫기, 실패 시 에러 팝업.
    /// (이전엔 AppRoot 의 PINView 콜백 안에서 SDK 를 직접 호출했음 — View 에서 분리.)
    func completePinChange(isLockAuth: Bool, currentPIN: String, newPIN: String) async {
        if isLockAuth {
            do {
                // 변경 정본 API. 기존 CEK 를 old passcode 로 복구해 new passcode 로 다시 감싼다.
                // registerLock 재호출로도 되지만 그건 CEK 를 새로 만들고 wallet token(CONFIGLOCK)
                // 발급이 필요해 서버에 의존하며, 전역 잠금 상태(isLock)까지 건드린다.
                // changeLock 은 로컬 연산만 하고 잠금 상태를 그대로 둔다.
                try WalletAPI.shared.changeLock(oldPasscode: currentPIN, newPasscode: newPIN)
                dismissModal()
            } catch {
                OverlayManager.shared.showErrorPopup(
                    title: "Failed to change wallet lock",
                    error: error
                )
            }
        } else {
            do {
                try WalletAPI.shared.changePin(
                    id: KeyIdName.pin,
                    oldPIN: currentPIN,
                    newPIN: newPIN
                )
                dismissModal()
            } catch {
                OverlayManager.shared.showErrorPopup(
                    title: "Failed to change PIN",
                    error: error
                )
            }
        }
    }

    // MARK: 모달 — 인증 게이트 (PIN / BIO 선택)

    /// 발급 흐름 등에서 서명 직전 인증 단계.
    /// 바이오 키가 등록되어 있고 LAContext 가 사용 가능하면 PIN/BIO 선택 시트를 띄우고,
    /// 그 외에는 곧장 PIN 인증 모달로 직행한다.
    /// - 사용자가 BIO 를 고른 경우 passcode 없이 `.bio` 만 돌아오며, 실제 생체 prompt 는
    ///   호출 측이 `WalletAPI.shared.getSignedDidAuth(passcode: nil)` 를 호출하는 시점에 SDK 가 트리거.
    /// - 사용자가 PIN 을 고르면 PIN 입력 모달을 거쳐 `.pin(passcode)` 가 돌아옴.
    /// - 어느 단계에서든 사용자가 취소하면 nil.
    func presentAuth() async -> AuthChoice? {
        let canUseBio = Biometrics.hasBioKey && Biometrics.canEvaluate()

        if !canUseBio {
            guard let pin = await presentPinAuth() else { return nil }
            beginAuthLoading()
            return .pin(pin)
        }

        guard let pick = await presentAuthSelection() else { return nil }
        switch pick {
        case .bio:
            // BIO 선택 → 후속 모달 없음. 선택 시트를 닫고 로딩으로 전환.
            modal = nil
            beginAuthLoading()
            return .bio
        case .pin:
            // PIN 선택 → 선택 시트를 nil 로 닫지 않고 곧바로 PIN 모달로 교체(content swap).
            // completeAuthSelection 이 modal 을 nil 로 만들지 않으므로 .authSelection→.pinAuth
            // 직접 전환이 되어 present-while-dismissing 없이 PIN 패드가 뜬다.
            guard let pin = await presentPinAuth() else { return nil }
            beginAuthLoading()
            return .pin(pin)
        }
    }

    /// 인증(PIN/bio) 성공 직후 — 모달 dismiss 와 같은 프레임에 로딩을 페이드 없이 즉시 띄워,
    /// 슬라이드다운(약 0.35s) 중 맨 화면이 노출되는 갭을 없앤다. 호출 측(issue/submit/revoke)의
    /// showLoading 은 이미 표시 중이라 no-op, defer hideLoading 이 정리 → 누수 없음.
    private func beginAuthLoading() {
        OverlayManager.shared.showLoading(animated: false)
    }

    /// VP 제출용 — verifier 가 요구한 VerifyAuthType 에 따라 인증수단을 강제 분기 (VAUTH-01~04).
    /// authType nil/그 외 → verifier 요구 없음으로 보고 기존 로컬 가용성 기반 presentAuth().
    /// 발급/폐기 등 verifier 무관 인증은 기존 presentAuth() 를 그대로 쓴다.
    /// VAUTH-04(PIN_AND_BIO)는 레퍼런스가 없어 "PIN 서명 + 생체 로컬 게이트"로 구현 — 서버 계약 확인 필요(best-guess).
    func presentAuth(for authType: VerifyAuthType?) async -> AuthChoice? {
        guard let authType else { return await presentAuth() }

        let needPin = authType.contains(.pin)
        let needBio = authType.contains(.bio)
        let needBoth = authType.contains(.and)

        // VAUTH-04 PIN_AND_BIO: PIN 인증 후 생체 게이트, 서명은 #pin.
        if needPin && needBio && needBoth {
            if let bioErr = Biometrics.signingReadiness() {
                OverlayManager.shared.showPopup(title: "Notification", message: bioErr.message, primaryButtonTitle: "OK")
                return nil
            }
            guard let pin = await presentPinAuth() else { return nil }
            guard await Biometrics.evaluate(reason: "Authenticate to submit") else { return nil }
            beginAuthLoading()
            return .pin(pin)
        }

        // VAUTH-03 PIN_OR_BIO: 둘 다 허용 → 로컬 가용성 정책과 동일.
        // bio 사용 가능 시 선택 시트, 미등록/불가 시 PIN 직행 (에러 팝업 없이 조용히 fallback).
        if needPin && needBio {
            return await presentAuth()
        }

        // VAUTH-02 BIO: 시트 없이 생체 직행. 생체 필수인데 미등록/불가면 중단.
        if needBio {
            if let bioErr = Biometrics.signingReadiness() {
                OverlayManager.shared.showPopup(title: "Notification", message: bioErr.message, primaryButtonTitle: "OK")
                return nil
            }
            beginAuthLoading()
            return .bio
        }

        // VAUTH-01 PIN: 시트 없이 PIN 직행.
        if needPin {
            guard let pin = await presentPinAuth() else { return nil }
            beginAuthLoading()
            return .pin(pin)
        }

        // .free 등 특정 요구 없음 → 기존 동작.
        return await presentAuth()
    }

    /// OID4VP 제출용 — 제출 대상의 **발급 시 바인딩 키**로 인증수단을 정한다.
    ///
    /// SD-JWT 는 사용자가 인증수단을 고를 수 없다. SDK 가 크리덴셜마다
    /// `walletCore.sign(keyId: item.kid, pin:)` 로 서명하는데 `kid` 는 발급 때 고정되기 때문이다.
    /// 그래서 선택 시트를 띄우면 안 되고(고를 게 없다), 바인딩이 섞여 있어도 문제되지 않는다 —
    /// Secure Enclave 키(#bio)는 넘어온 passcode 를 무시하고 서명 시점에 OS 가 생체 프롬프트를
    /// 띄우고, 소프트웨어 키(#pin)만 passcode 를 요구한다. 즉 **#pin 이 하나라도 있으면 PIN 만
    /// 받아 넘기면 둘 다 충족된다.**
    ///
    /// - parameter bindingKeyIds: 제출 대상 SD-JWT 의 `bindingKeyId` 목록. W3C 만이면 비어 있다.
    /// - returns: `.pin(passcode)` / `.bio`(앱 인증 없음 — SDK 가 처리) / 취소 시 nil.
    func presentAuth(forBindingKeyIds bindingKeyIds: [String]) async -> AuthChoice? {
        // SD-JWT 가 없으면(W3C 전용) 기존 정책 — bio 키가 있으면 선택 시트, 없으면 PIN 직행.
        guard !bindingKeyIds.isEmpty else { return await presentAuth() }

        if bindingKeyIds.contains(KeyIdName.pin) {
            guard let pin = await presentPinAuth() else { return nil }
            beginAuthLoading()
            return .pin(pin)
        }

        // 전부 #bio 바인딩 — 앱은 아무 화면도 띄우지 않는다. 서명 시점에 SDK 가 생체를 요구한다.
        beginAuthLoading()
        return .bio
    }

    private func presentAuthSelection() async -> AuthSelectionPick? {
        if let prev = authSelectionContinuation {
            authSelectionContinuation = nil
            prev.resume(returning: nil)
        }
        modal = .authSelection
        return await withCheckedContinuation { cont in
            authSelectionContinuation = cont
        }
    }

    /// 선택 시트의 버튼 액션에서 호출 — continuation 만 resume한다.
    /// 모달 닫기/교체는 재개된 presentAuth 가 담당한다(.bio → modal=nil, .pin → modal=.pinAuth swap).
    /// 여기서 modal=nil 을 하면 .pin 선택 시 nil→.pinAuth 재표시가 되어 PIN 패드가 안 뜰 수 있다.
    func completeAuthSelection(_ pick: AuthSelectionPick) {
        if let cont = authSelectionContinuation {
            authSelectionContinuation = nil
            cont.resume(returning: pick)
        }
    }

    /// AuthMethodView 의 back 액션 — 인증 흐름 취소 (continuation 에 nil resume + 모달 닫기).
    func cancelAuthSelection() {
        if let cont = authSelectionContinuation {
            authSelectionContinuation = nil
            cont.resume(returning: nil)
        }
        modal = nil
    }

    // MARK: 모달 — 발급 추가정보 웹 폼

    /// 발급 추가정보 입력 웹 폼 모달. 폼 완료(true) / 실패·취소(false) 를 비동기로 반환.
    func presentIssueWebForm(url: URL) async -> Bool {
        if let prev = issueWebFormContinuation {
            issueWebFormContinuation = nil
            prev.resume(returning: false)
        }
        modal = .issueWebForm(url)
        return await withCheckedContinuation { cont in
            issueWebFormContinuation = cont
        }
    }

    /// 웹 폼 결과 확정 (JS 콜백 또는 X 버튼) — continuation resume + 모달 닫기.
    func completeIssueWebForm(success: Bool) {
        if let cont = issueWebFormContinuation {
            issueWebFormContinuation = nil
            cont.resume(returning: success)
        }
        modal = nil
    }

    // MARK: 모달 — QR 스캔

    /// QR 스캔 모달. 인식된 페이로드 / 취소·닫기 시 nil 을 비동기로 반환.
    func presentQrScan() async -> String? {
        if let prev = qrScanContinuation {
            qrScanContinuation = nil
            prev.resume(returning: nil)
        }
        modal = .qrScan
        return await withCheckedContinuation { cont in
            qrScanContinuation = cont
        }
    }

    /// QR 스캔 결과 확정 (인식 payload / 닫기·취소 nil) — continuation resume + 모달 닫기.
    func completeQrScan(_ payload: String?) {
        if let cont = qrScanContinuation {
            qrScanContinuation = nil
            cont.resume(returning: payload)
        }
        modal = nil
    }

    // MARK: 모달 — OID4VCI tx_code 입력

    /// OID4VCI tx_code 입력 모달. 입력 완료 코드 / 취소·닫기 시 nil 을 비동기로 반환.
    func presentTxCode(length: Int, description: String) async -> String? {
        if let prev = txCodeContinuation {
            txCodeContinuation = nil
            prev.resume(returning: nil)
        }
        modal = .txCode(length: length, description: description)
        return await withCheckedContinuation { cont in
            txCodeContinuation = cont
        }
    }

    /// tx_code 입력 결과 확정 (입력 코드 / 닫기·취소 nil) — continuation resume + 모달 닫기.
    func completeTxCode(_ code: String?) {
        if let cont = txCodeContinuation {
            txCodeContinuation = nil
            cont.resume(returning: code)
        }
        modal = nil
    }

    // MARK: 모달 — OID4VCI 클레임 입력 WebView

    /// OID4VCI 클레임 입력 WebView 모달. 완료 redirect URL 문자열 / 취소·닫기 시 nil 을 반환.
    func presentOID4VciWebView(url: URL, allowedHost: String) async -> String? {
        if let prev = oid4vciWebViewContinuation {
            oid4vciWebViewContinuation = nil
            prev.resume(returning: nil)
        }
        oid4vciOfferHandling = false
        modal = .oid4vciWebView(url: url, allowedHost: allowedHost)
        return await withCheckedContinuation { cont in
            oid4vciWebViewContinuation = cont
        }
    }

    /// WebView 가 `openid-credential-offer://` navigation 을 가로챘을 때 호출 (가이드 §7·§10).
    ///
    /// navigation 중단은 `WebView` 가 이미 했다. 여기서는 중복 처리 차단 → 오퍼 URI 추출·검증 →
    /// 1회 소비 확인 → 모달 종료 순으로 진행한다. **검증에 실패하면 WebView 를 닫지 않는다** —
    /// 오류만 알리고 사용자가 화면에서 다시 시도하거나 X 로 닫게 둔다.
    func handleOID4VciCompletion(_ url: URL) {
        guard !oid4vciOfferHandling else { return }
        oid4vciOfferHandling = true
        do {
            let offerURI = try OID4VciIssuerDirectory.credentialOfferURI(from: url)
            guard !consumedOfferURIs.contains(offerURI) else {
                throw OID4VciDirectoryError.offerAlreadyConsumed
            }
            consumedOfferURIs.insert(offerURI)
            completeOID4VciWebView(url.absoluteString)
        } catch {
            oid4vciOfferHandling = false
            OverlayManager.shared.showErrorPopup(title: "Failed to receive credential offer", error: error)
        }
    }

    /// WebView 결과 확정 (완료 redirect URL / 닫기·취소 nil) — continuation resume + 모달 닫기.
    func completeOID4VciWebView(_ payload: String?) {
        if let cont = oid4vciWebViewContinuation {
            oid4vciWebViewContinuation = nil
            cont.resume(returning: payload)
        }
        modal = nil
    }

    // MARK: 모달 — 생체인증

    /// Biometric 모달. 결과를 비동기로 반환.
    func presentBiometric(fromSettings: Bool = false) async -> BiometricResult {
        if let prev = biometricContinuation {
            biometricContinuation = nil
            prev.resume(returning: .skipped)
        }
        modal = .biometric(fromSettings: fromSettings)
        return await withCheckedContinuation { cont in
            biometricContinuation = cont
        }
    }

    /// 설정 > Add Biometrics — PIN 인증 → 확인 화면 → bio 키 추가 + holder DID 문서 갱신.
    /// 온보딩과 달리 문서가 이미 발행돼 있어, generateKeyPair 만으론 서버 문서에 #bio 가
    /// 반영되지 않는다. UpdateUserProtocol 로 updateHolderDIDDocument → request/confirm-update-diddoc
    /// 까지 태워 발행 문서에 #bio 를 추가한다. PIN 은 문서 갱신 서명(#pin)에 필요해 먼저 받는다.
    func addBiometricsFromSettings() async {
        // 이미 등록됨(SET-E-03) / 미등록·미지원·잠김(BIO-E-01/02/03) 사전 점검 —
        // PIN 입력 전에 막는다 (campusID 동일 위치).
        if let blocked = Biometrics.enrollmentBlock() {
            OverlayManager.shared.showPopup(
                title: "Notification",
                message: blocked,
                primaryButtonTitle: "OK"
            )
            return
        }

        // BIO 확인 화면 먼저 (Enable=enabled / Cancel=skipped). Enable 을 누르면 그 화면을 닫지 않고
        // **위에** PIN 을 얹는다 — 문서 갱신을 #pin 키로 서명해야 서버가 수락하기 때문.
        // PIN 을 닫으면 바이오 화면으로 돌아오므로 거기서 다시 대기해야 한다. 안 그러면 화면은 떠
        // 있는데 기다리는 쪽이 없어 Enable 버튼이 죽는다.
        // 온보딩(step2)은 PIN "등록"이 그 단계의 본작업이라 순서가 반대다 — StepViewModel 이 그대로 유지한다.
        var passcode: String?
        repeat {
            guard await presentBiometric(fromSettings: true) == .enabled else {
                dismissModal()
                return
            }
            passcode = await presentPinAuth(stacked: true)
        } while passcode == nil

        guard let pin = passcode else { return }
        // 두 겹 다 걷어낸다 (PIN 겹은 completePin 이 이미 정리). 여기까지 오기 전에 만들어진 키는
        // 없으므로(bio 키는 addBioKey 안에서 생성) 중간에 취소해도 롤백할 게 없다.
        dismissModal()

        OverlayManager.shared.showLoading()
        defer { OverlayManager.shared.hideLoading() }
        do {
            try await UpdateUserProtocol.addBioKey(passcode: pin)
            OverlayManager.shared.showPopup(
                title: "Notification",
                message: "Biometric authentication is set up.",
                primaryButtonTitle: "OK"
            )
        } catch let bioErr as BiometricError {
            // BIO-E-04/05: 생체 prompt 취소·실패·기타 — 설계서 문구로 안내.
            OverlayManager.shared.showPopup(
                title: "Notification",
                message: bioErr.message,
                primaryButtonTitle: "OK"
            )
        } catch {
            // 서버/SDK 에러 — 백엔드 code/description 보존.
            OverlayManager.shared.showErrorPopup(title: "Failed to enable biometrics", error: error)
        }
    }

    /// Biometric 결과 확정 (Enable/Skip 버튼) — continuation 만 resume한다.
    /// 모달 닫기/교체는 재개된 호출 측이 담당한다 (설정 흐름은 .enabled → modal=.pinAuth 로 swap,
    /// 그 외에는 dismissModal()). `completeAuthSelection` 과 같은 이유 — 여기서 modal=nil 을 하면
    /// 바이오 화면이 내려간 뒤 PIN 을 다시 띄우는 꼴이라 present-while-dismissing 이 된다.
    func completeBiometric(_ result: BiometricResult) {
        if let cont = biometricContinuation {
            biometricContinuation = nil
            cont.resume(returning: result)
        }
    }

    // MARK: 모달 — 닫기 / continuation 정리

    /// 잠금이 떠 있으면 아무것도 하지 않는다. `presentLockAuth` 는 대기 중이던 continuation 을
    /// 먼저 취소로 깨우고 잠금을 세우는데, 깨어난 흐름들(StepViewModel.handleStep2Next,
    /// addBiometricsFromSettings)이 그 다음 턴에 이 메서드를 부른다 — 여기서 modal 을 비우면
    /// 방금 세운 잠금화면이 걷혀 인증 없이 지갑이 열린다. 잠금은 completeLockAuth(인증 성공)
    /// 또는 exit(0) 로만 끝난다 (표시 쪽 "잠금은 항상 최상위" 규칙의 해제 쪽 짝).
    func dismissModal() {
        guard modal != .lockAuth else { return }
        stackedModal = nil
        modal = nil
        cancelPendingModalContinuations()
    }

    /// 얹은 겹만 닫는다 — 아래 모달과 그 continuation 은 살려 둔다.
    /// (설정 Add Biometrics 에서 PIN 을 X 로 닫으면 바이오 화면으로 돌아오는 경로.)
    func dismissStackedModal() {
        stackedModal = nil
        if let cont = pinContinuation {
            pinContinuation = nil
            cont.resume(returning: nil)
        }
    }

    /// 대기 중인 모달 continuation 을 모두 취소값으로 resume한다 — 모달 상태(`modal`)는 건드리지 않는다.
    /// `lockAuthContinuation` 은 제외 — 잠금은 성공(complete) 또는 exit(0) 로만 종료한다.
    private func cancelPendingModalContinuations() {
        if let cont = pinContinuation {
            pinContinuation = nil
            cont.resume(returning: nil)
        }
        if let cont = biometricContinuation {
            biometricContinuation = nil
            cont.resume(returning: .skipped)
        }
        if let cont = authSelectionContinuation {
            authSelectionContinuation = nil
            cont.resume(returning: nil)
        }
        if let cont = issueWebFormContinuation {
            issueWebFormContinuation = nil
            cont.resume(returning: false)
        }
        if let cont = qrScanContinuation {
            qrScanContinuation = nil
            cont.resume(returning: nil)
        }
        if let cont = txCodeContinuation {
            txCodeContinuation = nil
            cont.resume(returning: nil)
        }
        if let cont = oid4vciWebViewContinuation {
            oid4vciWebViewContinuation = nil
            cont.resume(returning: nil)
        }
    }

    // MARK: - 스캔·딥링크 진입점
    //
    // 실제 분기와 흐름은 QRRouter 가 담당한다 — 화면이 코디네이터 하나만 알면 되도록
    // 진입점만 여기 남긴다.

    /// 스캔된 QR / 딥링크 처리 — scheme 으로 OID4VP / OID4VCI / OpenDID 를 가른다.
    /// - parameter intent: 스캔을 시작한 진입점이 기대하는 흐름. 딥링크는 진입 버튼이 없어
    ///   기본값 `.any` 로 제한하지 않는다.
    func handleScannedQR(_ qrString: String, intent: ScanIntent = .any) async {
        await QRRouter.handle(qrString, intent: intent, on: self)
    }

    /// OID4VCI 목록 기반(user-initiated) 발급 시작 — 클레임 입력 WebView 를 거쳐 오퍼를 받아온다.
    func startOID4VciWebIssuance(issuer: OID4VCIIssuerItem,
                                 metadata: IssuerMetadataResponse,
                                 configurationId: String) async {
        await QRRouter.startOID4VciWebIssuance(
            issuer: issuer,
            metadata: metadata,
            configurationId: configurationId,
            on: self
        )
    }

    // MARK: - 앱 초기화

    func resetAll() {
        // SDK 지갑(키·CoreData·user binding·lock) 전체 삭제 + 앱 Preference 초기화.
        // 이 둘을 안 하면 splash bootstrap 이 isExistWallet()/isUserRegistered() 를 true 로
        // 보고 곧장 main 으로 복귀해 실제 초기화가 일어나지 않는다.
        // (did-ca-ios SplashViewController 의 deleteWallet(deleteAll: true) 와 동일.)
        // 삭제 후 splash 의 bootstrap 이 isExistWallet()==false → createWallet 재생성하고
        // userId 없음 → onboarding step1 로 라우팅한다 (백엔드 도달 필요).
        do {
            try WalletAPI.shared.deleteWallet(deleteAll: true)
        } catch {
            // SET-E-02: 삭제 실패 → 안내(일부 데이터 잔존 가능), 초기화 중단(Settings 유지).
            OverlayManager.shared.showPopup(
                title: "Notification",
                message: "Failed to reset. Try again.",
                primaryButtonTitle: "OK"
            )
            return
        }
        Preference.reset()

        holderDIDCache = nil
        credentials = []
        pickedCred = nil
        issuedTitles = []
        modal = nil
        stackedModal = nil
        // 초기화 시점에 보관해 둔 잠금 이전 모달이 남아 있으면 이후 잠금 해제에서 되살아난다.
        modalBeforeLock = nil
        selectedCitizenship = nil
        verifyProfile = nil
        verifySummary = nil
        oid4vpRequest = nil
        oid4vpSummary = nil
        zkpProto = nil
        zkpAttrSelections = [:]
        zkpReveals = []
        zkpSelfRaws = [:]
        // 문서 자체는 버전이 고정돼 불변이지만, 이전 지갑의 발급자 흔적을 남기지 않는다.
        Task { await DIDDocumentResolver.shared.removeAll() }
        setRoot(.splash)
    }
}
