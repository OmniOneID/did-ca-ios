# Changelog

## v3.0.0 (2026-11-13)

### 🚀 New Features
- Credential issuance over OpenID4VCI (pre-authorized code flow, including `tx_code` entry)
- Verifiable presentation over OpenID4VP, with DCQL-based credential matching
- SD-JWT VC credentials, including selective disclosure of nested claims
- Credential revocation and suspension checks based on Token Status List
- mDoc credentials over OpenID4VCI and OpenID4VP
- In-person mDoc presentation to a nearby reader (ISO/IEC 18013-5: QR engagement and BLE session), including optional data elements the reader did not request
- Server revocation of OpenID4VCI credentials when they are deleted
- Server URL settings to override each backend address at run time
- User information registration during onboarding
- Credential titles and cached status shown while offline

### 🔄 Changes
- Rewrote the wallet app in SwiftUI
- Raised the minimum supported version from iOS 15 to iOS 17
- Resolve the wallet SDK (`DIDWalletSDK` 3.0.0) and the proximity SDK (`MdocDevice` 3.0.0) through SPM, each pinned to an exact release version
- Read and presentation wallet tokens are issued locally, so listing credentials works offline
- Aligned dialog titles and backdrop behavior with the screen design specification

## v2.0.1 (2025-12-12)

### 🚀 New Features
- Implement DID document update functions

## v2.0.0 (2025-05-28)

### 🚀 New Features
- Zero-Knowledge Proof Support

## v1.0.0 (2024-10-18)

### 🚀 New Features
- DID Document and VC Management through mobile wallet.