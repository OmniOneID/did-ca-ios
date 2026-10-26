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

enum TokenGeneratorError: Error {
    case userIdMissing
}

// DIDCA does not use AccessToken/RefreshToken, so there is no needToken parameter.
// Wallet tokens are obtained via two paths depending on purpose — read/present are issued locally by the SDK
// (0 network calls); everything else (create, issue, delete, update, personalize) round-trips to CAS.
nonisolated enum TokenGenerator {

    enum ECDHTarget {
        case device
        case holder
    }

    /// Purposes the SDK allows issuing without CAS — mirror of `WalletToken.localTokenPurposes` (internal, so not referenceable).
    /// Based on SDK doc WalletAPI.md 2.6. If the SDK-side list changes, update this too.
    private static let localTokenPurposes: Set<WalletTokenPurposeEnum> = [
        .LIST_VC, .DETAIL_VC, .PRESENT_VP, .LIST_VC_AND_PRESENT_VP
    ]

    static func requestWalletToken(purpose: WalletTokenPurposeEnum) async throws -> String {
        // Read/present purposes are issued locally — listing and proximity presentation work even with the backend unreachable.
        // Before personalization the SDK throws notPersonalized(05046), but in this app root is onboarding before
        // personalization, so execution never reaches here.
        if localTokenPurposes.contains(purpose) {
            return try WalletAPI.shared.createLocalWalletToken(
                purpose: purpose,
                pkgName: Bundle.main.bundleIdentifier!
            )
        }

        guard let userId = Preference.getUserId() else {
            throw TokenGeneratorError.userIdMissing
        }

        let walletTokenSeed = try WalletAPI.shared.createWalletTokenSeed(
            purpose: purpose,
            pkgName: Bundle.main.bundleIdentifier!,
            userId: userId
        )

        let walletTokenData = try await CASConnection.getWalletTokenData(request: walletTokenSeed)

        let nonce = try await WalletAPI.shared.createNonceForWalletToken(
            walletTokenData: walletTokenData,
            APIGatewayURL: URLs.API_URL
        )

        let digestSource = (try walletTokenData.toJson() + nonce).data(using: .utf8)!
        let digest = DigestUtils.getDigest(source: digestSource, digestEnum: .sha256)

        return String(MultibaseUtils.encode(type: .base16, data: digest).dropFirst())
    }
}

// MARK: - ECDH / Server Token (Step3 RegUserProtocol)
extension TokenGenerator {

    /// Derives sharedSecret via device or holder key agreement (the key for decrypting the server token).
    static func getSharedSecret(type: ECDHTarget = .holder, txId: String) async throws -> Data {
        let nonce = try CryptoUtils.generateNonce(size: 16)
        let clientNonce = MultibaseUtils.encode(type: .base58BTC, data: nonce)
        let keyPair = try CryptoUtils.generateECKeyPair(ecType: .secp256r1)

        let didDoc: DIDDocument
        let docType: DidDocumentType
        switch type {
        case .device:
            didDoc = try WalletAPI.shared.getDidDocument(type: .DeviceDidDocument)
            docType = .DeviceDidDocument
        case .holder:
            didDoc = try WalletAPI.shared.getDidDocument(type: .HolderDidDocumnet)
            docType = .HolderDidDocumnet
        }
        let proofType = didDoc.id + "?versionId=" + didDoc.versionId + "#keyagree"

        var reqEcdh = ReqEcdhBuilder()
            .setClient(didDoc.id)
            .setClientNonce(clientNonce)
            .setPublicKey(MultibaseUtils.encode(type: .base58BTC, data: keyPair.publicKey))
            .setCurve(.secp256r1)
            .setProof(Proof(
                created: Date.getUTC0Date(seconds: 0),
                proofPurpose: .keyAgreement,
                verificationMethod: proofType,
                type: .secp256r1Signature2018
            ))
            .build()

        let source = try DigestUtils.getDigest(source: reqEcdh.toJsonData(), digestEnum: .sha256)
        let signature = try WalletAPI.shared.sign(keyId: "keyagree", data: source, type: docType)
        reqEcdh.proof?.proofValue = MultibaseUtils.encode(type: .base58BTC, data: signature)

        let request = RequestEcdh(id: UUID().uuidString, txId: txId, reqEcdh: reqEcdh)
        let ecdh = try await TASConnection.requestEcdh(request: request)

        let secretKey = try CryptoUtils.generateSharedSecret(
            ecType: .secp256r1,
            privateKey: keyPair.privateKey,
            publicKey: MultibaseUtils.decode(encoded: ecdh.accEcdh.publicKey)
        )

        let serverNonce = try MultibaseUtils.decode(encoded: ecdh.accEcdh.serverNonce)
        let mergedNonce = mergeAndDigest(nonce, serverNonce)
        let keyData = mergeAndDigest(secretKey, mergedNonce)
        return keyData.prefix(32)
    }

    /// Creates the server token (hServerToken). Used by RegUserProtocol's retrieveKYC / requestRegisterUser.
    static func requestServerToken(
        purpose: WalletTokenPurposeEnum,
        txId: String,
        sharedSecret: Data
    ) async throws -> String {
        let walletInfo = try WalletAPI.shared.getSignedWalletInfo()
        let attestedAppInfo = try await CASConnection.requestAttestedAppInfo()

        let seed = ServerTokenSeed(
            purpose: purpose,
            walletInfo: walletInfo,
            attestedAppInfo: attestedAppInfo
        )
        let request = RequestCreateToken(id: UUID().uuidString, txId: txId, seed: seed)
        let response = try await TASConnection.createToken(request: request)

        let encStd = try MultibaseUtils.decode(encoded: response.encStd)
        let iv = try MultibaseUtils.decode(encoded: response.iv)
        let std = try CryptoUtils.decrypt(
            cipher: encStd,
            info: CipherInfo(cipherType: .aes256CBC, padding: .pkcs5),
            key: sharedSecret,
            iv: iv
        )

        let serverTokenData = try ServerTokenData(from: std)
        try await verifyCertVc(serverTokenData: serverTokenData, roleType: .Tas)

        let digest = DigestUtils.getDigest(source: std, digestEnum: .sha256)
        return MultibaseUtils.encode(type: .base64, data: digest)
    }

    // certVc integrity check: DID match, role claim match, issuer signature verification.
    private static func verifyCertVc(serverTokenData: ServerTokenData, roleType: RoleTypeEnum) async throws {
        let did = serverTokenData.provider.did
        let urlString = serverTokenData.provider.certVcRef

        var certVc: VerifiableCredential = try await HttpClient.sendGetRequest(urlString: urlString)

        guard did == certVc.credentialSubject.id else {
            throw NSError(domain: "did matching fail", code: 1)
        }

        let didDoc = try await CommunicationClient.getDIDDocument(hostUrlString: URLs.API_URL,
                                                                 did: certVc.issuer.id)

        let vcSchema: VCSchema = try await HttpClient.sendGetRequest(urlString: certVc.credentialSchema.id)
        var roleMatched = false
        for schemaClaim in vcSchema.credentialSubject.claims {
            for item in schemaClaim.items where item.caption == "role" {
                for certVcClaim in certVc.credentialSubject.claims where certVcClaim.caption == item.caption {
                    if roleType.rawValue == certVcClaim.value {
                        roleMatched = true
                    }
                }
            }
        }
        guard roleMatched else {
            throw NSError(domain: "role matching fail", code: 1)
        }

        for method in didDoc.verificationMethod where method.id == "assert" {
            let pubKey = try MultibaseUtils.decode(encoded: method.publicKeyMultibase)
            let signature = try MultibaseUtils.decode(encoded: certVc.proof.proofValue!)
            certVc.proof.proofValue = nil
            certVc.proof.proofValueList = nil
            let digest = DigestUtils.getDigest(source: try certVc.toJsonData(), digestEnum: .sha256)
            _ = try WalletAPI.shared.verify(publicKey: pubKey, data: digest, signature: signature)
        }
    }

    private static func mergeAndDigest(_ items: Data...) -> Data {
        var combined = Data()
        for item in items { combined.append(item) }
        return DigestUtils.getDigest(source: combined, digestEnum: .sha256)
    }
}
