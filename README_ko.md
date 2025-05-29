# DIDCA Guide

![Platform](https://img.shields.io/cocoapods/p/SquishButton.svg?style=flat)
[![Swift](https://img.shields.io/badge/Swift-5-orange.svg?style=flat)](https://developer.apple.com/swift)

## 개요
본 문서는 OpenDID 인증 클라이언트를 사용하기 위한 가이드이며, 사용자에게 OpenDID에 필요한 WalletToken, Lock/Unlock, Key, DID Document(DID 문서), Verifiable Credential(이하 VC) 정보를 생성, 저장, 관리하는 기능을 제공합니다.


## S/W 사양
| 구분              | 내용                            |
|-------------------|-------------------------------|
| OS                | iOS 15                        |
| Language          | Swift 5.8                     |
| IDE               | Xcode 16.2                    |
| Build System      | Xcode 기본 빌드 시스템            |
| Compatibility     | iOS 15 or higher              |
| Test Environment  | iPhone 15 (17.5) 시뮬레이터      |


## DIDCA 프로젝트 클론 및 체크아웃
```git
git clone https://github.com/OmniOneID/did-ca-ios.git
```

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
DIDWalletSDK 프로젝트 클론 및 체크아웃 후 release 폴더에 최신버전을 다운받아 사용하길 권장합니다.
```
git https://https://github.com/OmniOneID/did-client-sdk-ios
```
- `DIDWalletSDK.framework`

<br>

SDK가 사용하는 타사 라이브러리에 대한 자체 라이선스는 해당 링크를 참고해주세요. <br>
[Client SDK License-dependencies](https://github.com/OmniOneID/did-client-sdk-ios/blob/main/dependencies-license.md))

<br>

Xcode에서 DIDWalletSDK framework를 DIDCA 프로젝트에 적용하는 방법
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

4. Import 및 사용

먼저 URLs.swift 파일에서 각 사업자의 URL정보를 수정합니다.
```swift
struct URLs
{
    public static let TAS_URL       : String = "http://192.168.3.130:18090"
    public static let VERIFIER_URL  : String = "http://192.168.3.130:18092"
    public static let CAS_URL       : String = "http://192.168.3.130:18094"
    public static let WALLET_URL    : String = "http://192.168.3.130:18095"
    public static let API_URL       : String = "http://192.168.3.130:18093"
    public static let DEMO_URL      : String = "http://192.168.3.130:18099"
}
```

그리고 프로젝트의 소스 파일에서 DIDWalletSDK의 모듈을 사용해야 합니다. 사용할 클래스나 메서드가 있는 소스 파일의 최상단에 다음과 같이 임포트합니다.
```swift
import DIDWalletSDK
```
이제 DIDWalletSDK에서 제공하는 기능을 소스 코드에서 사용할 수 있습니다. 
```swift
Task { @MainActor in
    do {
        let hWalletToken = try await SDKUtils.createWalletToken(purpose: WalletTokenPurposeEnum.LIST_VC, userId: Properties.getUserId()!)

        guard let credentials = try WalletAPI.shared.getAllCrentials(hWalletToken: hWalletToken) else {    
            return
        }
        for credential in self.credentials {
            print("vc: \(try! credential.toJson())")
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

5. 빌드 및 테스트

    - 빌드 및 실행    
        - Xcode 상단의 Build (Command + B) 버튼을 눌러 프로젝트를 빌드합니다. 만약 빌드 중 에러가 발생하면, Issue Navigator에서 에러 내용을 확인하고 문제를 해결합니다.

    - 테스트
        - 빌드가 성공적으로 완료되면, 앱을 실행하여 framework의 기능이 제대로 동작하는지 확인합니다. Xcode의 디버거와 로그를 활용해 문제가 발생했는지 여부를 파악할 수 있습니다.

6. 문제 해결
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
