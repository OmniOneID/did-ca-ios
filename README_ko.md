# DIDCA Guide

![Platform](https://img.shields.io/cocoapods/p/SquishButton.svg?style=flat)
[![Swift](https://img.shields.io/badge/Swift-5-orange.svg?style=flat)](https://developer.apple.com/swift)

## 개요
본 문서는 OpenDID 인증 클라이언트를 사용하기 위한 가이드이며, 사용자에게 OpenDID에 필요한 WalletToken, Lock/Unlock, Key, DID Document(DID 문서), Verifiable Credential(이하 VC) 정보를 생성, 저장, 관리하는 기능을 제공합니다.

OpenDID 프로토콜과 더불어 OpenID for Verifiable Credentials 계열도 지원합니다. OpenID4VCI(pre-authorized code 방식, `tx_code` 포함)를 통한 발급, OpenID4VP를 통한 제출, SD-JWT VC 크레덴셜, Token Status List 기반 폐기·정지 상태 확인을 제공합니다.


## S/W 사양
| 구분              | 내용                                    |
|-------------------|---------------------------------------|
| OS                | iOS 17                                |
| Language          | Swift 5                               |
| UI Framework      | SwiftUI                               |
| IDE               | Xcode 26.2                            |
| Build System      | Xcode 기본 빌드 시스템                    |
| Compatibility     | iOS 17 or higher                      |
| Test Environment  | iPhone 시뮬레이터(iOS 17.5) 및 실제 기기    |


## DIDCA 프로젝트 클론 및 체크아웃
```git
git clone https://github.com/OmniOneID/did-ca-ios.git
```

Xcode 프로젝트는 `source` 디렉토리 아래에 있습니다. `source/DIDCA.xcodeproj`를 여세요.

## 빌드 방법
Xcode의 기본 빌드 시스템을 사용하여 앱을 컴파일하고 테스트하는 방법이다.
1. Xcode 설치
    - Xcode를 실행하고, 상단 메뉴에서 File > Open을 선택하여 프로젝트 파일(.xcodeproj)을 엽니다.
2. 프로젝트 열기
    - 프로젝트가 열리면 Xcode 창 좌측의 Project Navigator에서 소스 파일, 리소스 파일 및 설정 파일을 확인 할 수 있다.
3. 시뮬레이터 또는 실제 기기 선택
    - Xcode 창 상단에 보면, 빌드하고 실행할 타겟 기기를 선택하는 메뉴가 있습니다. 여기서 iPhone, iPad 등의 시뮬레이터 또는 연결된 실제 기기를 선택할 수 있습니다.
    - Simulator: iOS 시뮬레이터를 선택하여 가상의 iPhone 또는 iPad에서 앱을 실행할 수 있습니다.
    - Device: 실제 기기를 연결한 경우 해당 기기를 선택할 수 있습니다.

4. 프로젝트 설정 확인
    - 빌드하기 전에 프로젝트 설정을 확인해야 합니다.
    - 왼쪽 프로젝트 트리에서 프로젝트 파일을 선택한 후, 우측에 있는 Project Settings에서 Target의 설정을 확인합니다. 여기서 iOS Deployment Target(지원하는 최소 iOS 버전), Signing & Capabilities(코드 서명), General(앱의 정보 및 빌드 설정) 등을 확인하고 필요 시 수정합니다


## SDK 적용 방법
아래 `iOS framework를 DIDWalletSDK`로 지칭합니다.
DIDWalletSDK 프로젝트 클론 및 체크아웃 후 release 폴더에 최신버전을 다운받아 사용하거나 SPM을 사용하길 권장합니다.
```
git https://github.com/OmniOneID/did-client-sdk-ios
```
- `DIDWalletSDK.framework`

<br>

SDK가 사용하는 타사 라이브러리에 대한 자체 라이선스는 해당 링크를 참고해주세요. <br>
[Client SDK License-dependencies](https://github.com/OmniOneID/did-client-sdk-ios/blob/main/dependencies-license.md)

<br>

## Xcode에서 DIDWalletSDK framework를 DIDCA 프로젝트에 적용하는 방법

### SPM을 통한 Framework 추가 (권장)

DIDCA 프로젝트 자체가 이 방식으로 SDK를 참조합니다. 의존성이 `source/DIDCA.xcodeproj`에 이미 선언되어 있어 클론 직후 별도 작업이 필요 없습니다. 다른 프로젝트에 적용하려면 다음과 같이 합니다.

- 앱 프로젝트의 `Package Dependencies`에서 `+`를 눌러 다음 항목을 추가합니다.
```text
https://github.com/OmniOneID/did-client-sdk-ios.git
```
- **Version ≥ 3.0.0**을 선택하거나, “Up to Next Major” 규칙을 선택합니다.
- 패키지를 타겟에 추가합니다.
- `OrderedCollections`(Swift Collections)는 전이 의존성으로 함께 받아지므로 따로 추가하지 않아도 됩니다.

### 기존 적용 방식 사용  

1. DIDWalletSDK framework 파일 준비

    - 만약 DIDWalletSDK framework가 없는 경우, framework 레포지토리에서 빌드하여 .framework 파일을 생성해야 합니다. simulator, device 각각 빌드하여 각 레포지토리 별 build_xcframework 스크립트를 활용하여 xcframework를 사용 할 수 있습니다.
    - xcframework는 simulator와 device 모두를 지원하는 framework입니다.

2. DIDWalletSDK framework 프로젝트에 추가

    - Xcode에서 DIDCA 프로젝트를 엽니다.
    - 왼쪽 Project Navigator에서 DIDCA 프로젝트를 선택한 후, 상단의 Target을 선택합니다.
    - General 탭에서 아래로 스크롤하면 Frameworks, Libraries, and Embedded Content 섹션이 나옵니다.
    - 이 섹션 하단에 있는 + 버튼을 클릭합니다.
    - 나타나는 팝업에서 **Add Other... > Add Files...** 를 선택하고, DIDWalletSDK framework 파일을 선택한 후, Add 버튼을 클릭합니다.
    - DIDWalletSDK frameworks가 추가되면, Embed & Sign 옵션을 활성화 해야 합니다.
    - 만약 위의 라이브러리 파일이 없는 경우, 각 SDK의 레포지토리에서 빌드하여 framework 파일을 생성해야 합니다.
[Move to Client SDK](https://github.com/OmniOneID/did-client-sdk-ios/tree/main)

3. Build Settings 수정

    - Framework Search Path 설정
        - 프로젝트에서 Build Settings 탭을 클릭한 후, 검색 창에서 Framework Search Paths를 찾습니다.
        - 만약 DIDWalletSDK framework가 외부 디렉토리에 있을 경우, 해당 경로를 Framework Search Paths에 추가해줍니다. 예를 들어, $(PROJECT_DIR)/Frameworks와 같이 설정할 수 있습니다.
    - Runpath Search Paths 설정
        - 검색 창에서 Runpath Search Paths를 찾습니다. 만약 추가된 프레임워크가 정상적으로 실행되지 않는 경우, @executable_path/Frameworks 값을 추가합니다. 이는 앱 실행 시 프레임워크를 찾기 위한 경로를 설정하는 것입니다.

4. SPM에 의존성 추가하기

    - 추가할 패키지가 없습니다. Swift Collections는 xcframework에 정적으로 포함되고 SDK 공개 인터페이스에도 더 이상 노출되지 않으므로, 앱이 따로 선언하지 않아도 됩니다.
    - 이전 버전은 `OrderedCollections`를 공개 API로 노출해 `https://github.com/apple/swift-collections.git`을 `Exact Version 1.1.4`로 추가하도록 안내했습니다. v3.0.0부터는 그 선언을 지워도 되며, 앱이 Swift Collections를 직접 사용하는 경우에만 남겨 두십시오.


### Import 및 사용

먼저 `source/DIDCA/Logic/Constants/URLs.swift` 파일에서 각 사업자의 URL정보를 수정합니다. 아래 값은 개발망 주소이므로 실제 운영 환경 주소로 교체해야 합니다. 이 주소에 접근되지 않으면 온보딩·발급·제출이 모두 실패합니다.
```swift
struct URLs
{
    static let TAS_URL       : String = "http://192.168.3.110:8090"
    static let VERIFIER_URL  : String = "http://192.168.3.110:8092"
    static let CAS_URL       : String = "http://192.168.3.110:8094"
    static let WALLET_URL    : String = "http://192.168.3.110:8095"
    static let API_URL       : String = "http://192.168.3.110:8093"
    static let DEMO_URL      : String = "http://192.168.3.110:8099"
}
```

그리고 프로젝트의 소스 파일에서 DIDWalletSDK의 모듈을 사용해야 합니다. 사용할 클래스나 메서드가 있는 소스 파일의 최상단에 다음과 같이 임포트합니다.
```swift
import DIDWalletSDK
```
이제 DIDWalletSDK에서 제공하는 기능을 소스 코드에서 사용할 수 있습니다. 대부분의 SDK 호출에는 wallet token이 필요하며, DIDCA는 `TokenGenerator.requestWalletToken(purpose:)`로 저장된 사용자 ID에 대한 CAS 핸드셰이크를 수행해 토큰을 발급받습니다.
```swift
Task { @MainActor in
    do {
        let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .LIST_VC)

        guard let credentials = try WalletAPI.shared.getAllCredentials(hWalletToken: hWalletToken) else {
            return
        }
        for credential in credentials {
            print("vc: \(try credential.toJson())")
        }
    } catch let error as WalletSDKError {
        print("error code: \(error.code), message: \(error.message)")
    } catch let error as CommunicationSDKError {
        print("error code: \(error.code), message: \(error.message)")
    } catch let error as WalletCoreError {
        print("error code: \(error.code), message: \(error.message)")
    } catch {
        print("error :\(error)")
    }
}
```
OpenID4VCI로 발급받은 SD-JWT VC 크레덴셜은 W3C VC와 별도로 저장되며 `WalletAPI.shared.getAllOID4VCs(hWalletToken:)`로 읽습니다.

### 빌드 및 테스트

- 빌드 및 실행    
    - Xcode 상단의 Build (Command + B) 버튼을 눌러 프로젝트를 빌드합니다. 만약 빌드 중 에러가 발생하면, Issue Navigator에서 에러 내용을 확인하고 문제를 해결합니다.

- 테스트
    - 빌드가 성공적으로 완료되면, 앱을 실행하여 framework의 기능이 제대로 동작하는지 확인합니다. Xcode의 디버거와 로그를 활용해 문제가 발생했는지 여부를 파악할 수 있습니다.

### 문제 해결
- 만약 DIDWalletSDK framework가 제대로 로드되지 않거나 작동하지 않는 경우, 다음 사항들을 확인해보세요:

    - Correct Search Paths: 프레임워크 경로가 정확하게 설정되었는지 확인합니다.
    - Signing & Capabilities: 코드 서명 및 인증서 설정이 올바르게 되어 있는지 확인합니다.
    - Dependencies: DIDWalletSDK framework가 추가적으로 의존하는 다른 라이브러리가 있는지 확인합니다.

## 수정내역

ChangeLog는 아래에서 확인할 수 있습니다.
<br>
- [CA IOS](CHANGELOG.md)   

## 데모 영상 <br>
OpenDID 시스템의 실제 동작을 보여주는 데모 영상은 [Demo Repository](https://github.com/OmniOneID/did-demo-server) 에서 확인하실 수 있습니다. <br>
사용자 등록, VC 발급, VP 제출 등 주요 기능들을 영상으로 확인하실 수 있습니다.

## 기여
Contributing 및 pull request 제출 절차에 대한 자세한 내용은 [CONTRIBUTING.md](CONTRIBUTING.md)와 [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) 를 참조하세요.

## 라이선스
[Apache 2.0](LICENSE)
