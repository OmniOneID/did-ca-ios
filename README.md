# DIDCA Guide

![Platform](https://img.shields.io/cocoapods/p/SquishButton.svg?style=flat)
[![Swift](https://img.shields.io/badge/Swift-5-orange.svg?style=flat)](https://developer.apple.com/swift)

## Overview
This document is a guide for using the OpenDID authentication client, and provides users with the ability to create, store, and manage the WalletToken, Lock/Unlock, Key, DID Document, and Verifiable Credential (hereinafter referred to as VC) information required for OpenDID.


## S/W Specifications
| Category | Details                |
|------|----------------------------|
| OS  | iOS 15.0+|
| Language  | swift 5.0+|
| IDE  | xCode 14.x|
| Build System  | Xcode Basic build system |
| Compatibility | minSDK 15 or iOS 15 higher  |

## Clone and checkout the DIDCA project
```git
git clone https://github.com/OmniOneID/did-ca-ios.git
```

## Build Method
How to compile and test your app using Xcode's default build system.
1. Install Xcode
    - Run Xcode and open the desired project file (.xcodeproj or .xcworkspace) by selecting File > Open from the top menu.
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
Below, we refer to `iOS frameworks as DIDClientSDK`. We recommend that you clone and check out the DIDClientSDK project and download the latest version to the release folder to use it.
```
git https://https://github.com/OmniOneID/did-client-sdk-ios
```
- `DIDWalletSDK.framework`
- `DIDDataModelSDK.framework`
- `DIDUtilitySDK.framework`
- `DIDCommunicationSDK.framework`
- `DIDCoreSDK.framework`
<br>

Please refer to the respective links for their own licenses for third-party libraries used by each SDK.
<br>
[Client SDK License-dependencies](https://github.com/OmniOneID/did-client-sdk-ios/-/blob/main/LICENSE-dependencies.md)

<br>
How to apply DIDClientSDK frameworks to DIDCA project in Xcode
1. Preparing DIDClientSDK frameworks files

    - If DIDClientSDK frameworks are not present, you need to build from each framework repository to generate .framework files. You can use xcframework by building each simulator and device and using the build_xcframework script for each repository. 
    - xcframework is a framework that supports both simulator and device.

2. Add DIDClientSDK frameworks to your project

    - Open the DIDCA project in Xcode.
    - Select the DIDCA project in the Project Navigator on the left, then select Target at the top.
    - Scroll down in the General tab to the Frameworks, Libraries, and Embedded Content section.
    - Click the + button at the bottom of this section.
    - In the pop-up that appears, select **Add Other... > Add Files...**, select the DIDClientSDK frameworks files, and click the Add button.
    - Once the DIDClientSDK frameworks are added, you need to enable the Embed & Sign option.
      - If you do not have the above library files, you need to build them from the SDK repository to generate the framework files.
        [Move to Client SDK]((https://github.com/OmniOneID/did-client-sdk-ios/tree/main)


1. Modify Build Settings

    - Setting the Framework Search Path
        - Click the Build Settings tab in your project, and then find Framework Search Paths in the search box. 
        - If the DIDClientSDK frameworks are in an external directory, add the path to Framework Search Paths. For example, you can set it as $(PROJECT_DIR)/Frameworks.
    - Set Runpath Search Paths
        - In the search bar, find Runpath Search Paths. If the added framework is not running properly, add the @executable_path/Frameworks value. This sets the path to find the framework when running the app.

2. Import and Use

First, modify the URL information for each business in the URLs.swift file.
```swift
class URLs {
    public static let TAS_URL: String = "http://192.168.3.130:8090"
    public static let VERIFIER_URL: String = "http://192.168.3.130:8092"
    public static let CAS_URL: String = "http://192.168.3.130:8094"
    public static let WALLET_URL: String = "http://192.168.3.130:8095"
    public static let API_URL: String = "http://192.168.3.130:8093"
    public static let DEMO_URL: String = "http://192.168.3.130:8099"
}
```

And you need to use the DIDClientSDK module in your project's source files. Import it at the top of the source file that contains the class or method you want to use, like this:
```swift
import DIDWalletSDK
import DIDDataModelSDK
import DIDUtilitySDK
import DIDCommunicationSDK
import DIDCoreSDK
```
The functionality provided by DIDClientSDK is now available in source code.
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

5. Build and Test

    - Build and Run    
        - Build your project by pressing the Build (Command + B) button at the top of Xcode. If any errors occur during the build, check the error message in the Issue Navigator and resolve the issue.

    - Test
        - Once the build is completed successfully, run your app to verify that the framework is working properly. You can use Xcode's debugger and logs to determine if there are any issues.

6. Troubleshooting
    - If the DIDClientSDK frameworks are not loading or working properly, check the following:

        - Correct Search Paths: Check if the framework paths are set correctly.
        - Signing & Capabilities: Check if the code signing and certificate settings are set correctly.
        - Dependencies: Check if there are any other libraries that the DIDClientSDK frameworks additionally depend on.

