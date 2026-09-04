# DIDCA Guide

![Platform](https://img.shields.io/cocoapods/p/SquishButton.svg?style=flat)
[![Swift](https://img.shields.io/badge/Swift-5-orange.svg?style=flat)](https://developer.apple.com/swift)


## Overview
This document is a guide for using the OpenDID authentication client, and provides users with the ability to create, store, and manage the WalletToken, Lock/Unlock, Key, DID Document, and Verifiable Credential (hereinafter referred to as VC) information required for OpenDID.

In addition to the OpenDID protocol, the app supports the OpenID for Verifiable Credentials family — credential issuance over OpenID4VCI (pre-authorized code flow, including `tx_code`) and presentation over OpenID4VP — as well as SD-JWT VC credentials and Token Status List based revocation/suspension checks.


## S/W Specifications
| Category         | Details                                         |
|------------------|-------------------------------------------------|
| OS               | iOS 17                                          |
| Language         | Swift 5                                         |
| UI Framework     | SwiftUI                                         |
| IDE              | Xcode 26.2                                      |
| Build System     | Xcode Basic build system                        |
| Compatibility    | iOS 17 or higher                                |
| Test Environment | iPhone Simulator (iOS 17.5) and physical device |

## Clone and checkout the DIDCA project
```git
git clone https://github.com/OmniOneID/did-ca-ios.git
```

The Xcode project lives under the `source` directory — open `source/DIDCA.xcodeproj`.

## Build Method
How to compile and test your app using Xcode's default build system.
1. Install Xcode
    - Run Xcode and open the project file (.xcodeproj) by selecting File > Open from the top menu.
2. Open the project
    - When the project is opened, you can check the source files, resource files, and settings files in the Project Navigator on the left side of the Xcode window.
3. Select a simulator or actual device
    - At the top of the Xcode window, there is a menu for selecting the target device to build and run. Here, you can select a simulator such as iPhone or iPad or a connected actual device.
- Simulator: You can select the iOS simulator to run the app on a virtual iPhone or iPad.
- Device: If you have a real device connected, you can select the device.

4. Check the project settings
    - You need to check the project settings before building.
    - Select the project file in the left project tree, and check the Target settings in Project Settings on the right. Here, check iOS Deployment Target (the minimum iOS version supported), Signing & Capabilities (code signing), General (app information and build settings), etc., and modify them if necessary.


## SDK Application Method
Below, we refer to `iOS framework as DIDWalletSDK`. We recommend that you clone and check out the DIDWalletSDK project, then either download the latest version from the release folder or use SPM.
```
git https://github.com/OmniOneID/did-client-sdk-ios
```
- `DIDWalletSDK.framework`

<br>

Please refer to the respective links for their own licenses for third-party libraries used by SDKs.
<br>
[Client SDK License-dependencies](https://github.com/OmniOneID/did-client-sdk-ios/blob/main/dependencies-license.md)
                                
<br>

## How to apply DIDWalletSDK framework to DIDCA project in Xcode

### Apply Framework via SPM (recommended)

This is how the DIDCA project itself resolves the SDK — the dependency is already declared in `source/DIDCA.xcodeproj`, so a fresh clone needs no manual step. To wire it into another project:

- In the app project’s `Package Dependencies`, click the `+` to add the following items.
```text
https://github.com/OmniOneID/did-client-sdk-ios.git
```
- Select **Version ≥ 3.0.0** (or choose a version rule such as “Up to Next Major”).
- Add the package to your target.
- `OrderedCollections` (Swift Collections) is pulled in transitively, so it does not need to be added by hand.
<br>

### Using the framework’s own application method.

1. Preparing DIDWalletSDK framework files

    - If DIDWalletSDK framework is not present, you need to build from each framework repository to generate .framework file. You can use xcframework by building each simulator and device and using the build_xcframework script for each repository. 
    - xcframework is a framework that supports both simulator and device.

2. Add DIDWalletSDK framework to your project

    - Open the DIDCA project in Xcode.
    - Select the DIDCA project in the Project Navigator on the left, then select Target at the top.
    - Scroll down in the General tab to the Frameworks, Libraries, and Embedded Content section.
    - Click the + button at the bottom of this section.
    - In the pop-up that appears, select **Add Other... > Add Files...**, select the DIDWalletSDK frameworks file, and click the Add button.
    - Once the DIDWalletSDK framework is added, you need to enable the Embed & Sign option.
    - If you do not have the above library file, you need to build them from the SDK repository to generate the framework file.
        [Move to Client SDK](https://github.com/OmniOneID/did-client-sdk-ios/tree/main)

3. Modify Build Settings

    - Setting the Framework Search Path
        - Click the Build Settings tab in your project, and then find Framework Search Paths in the search box. 
        - If the DIDWalletSDK frameworks are in an external directory, add the path to Framework Search Paths. For example, you can set it as $(PROJECT_DIR)/Frameworks.
    - Set Runpath Search Paths
        - In the search bar, find Runpath Search Paths. If the added framework is not running properly, add the @executable_path/Frameworks value. This sets the path to find the framework when running the app.

4. Add dependencies to SPM

- No additional package is required. Swift Collections is linked statically into the xcframework and no longer appears in the SDK’s public interface, so it does not have to be declared by the app.
- Earlier releases exposed `OrderedCollections` through the public API and asked you to add `https://github.com/apple/swift-collections.git` at `Exact Version 1.1.4`. From v3.0.0 that declaration can be removed; keep it only if your app uses Swift Collections directly.

### Import and Use

First, modify the URL information for each business in `source/DIDCA/Logic/Constants/URLs.swift`. The values below point at a development LAN and must be replaced with your own deployment — onboarding, issuance and presentation all fail until these hosts are reachable.
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

And you need to use the DIDWalletSDK module in your project's source files. Import it at the top of the source file that contains the class or method you want to use, like this:
```swift
import DIDWalletSDK
```
The functionality provided by DIDWalletSDK is now available in source code. Most SDK calls need a wallet token; DIDCA issues one through `TokenGenerator.requestWalletToken(purpose:)`, which performs the CAS handshake for the stored user id.
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
SD-JWT VC credentials issued over OpenID4VCI are stored separately from W3C VCs and are read with `WalletAPI.shared.getAllOID4VCs(hWalletToken:)`.

### Build and Test

- Build and Run    
    - Build your project by pressing the Build (Command + B) button at the top of Xcode. If any errors occur during the build, check the error message in the Issue Navigator and resolve the issue.

- Test
    - Once the build is completed successfully, run your app to verify that the framework is working properly. You can use Xcode's debugger and logs to determine if there are any issues.

### Troubleshooting

- If the DIDWalletSDK framework is not loading or working properly, check the following:

    - Correct Search Paths: Check if the framework paths are set correctly.
    - Signing & Capabilities: Check if the code signing and certificate settings are set correctly.
    - Dependencies: Check if there are any other libraries that the DIDWalletSDK framework additionally depend on.

## Change Log

ChangeLog can be found : 
<br>
- [CA iOS](CHANGELOG.md)  

## OpenDID Demonstration Videos <br>
To watch our demonstration videos of the OpenDID system in action, please visit our [Demo Repository](https://github.com/OmniOneID/did-demo-server). <br>

These videos showcase key features including user registration, VC issuance, and VP submission processes.

## Contributing
Please read [CONTRIBUTING.md](CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for details on our code of conduct, and the process for submitting pull requests to us.

## License
[Apache 2.0](LICENSE)

