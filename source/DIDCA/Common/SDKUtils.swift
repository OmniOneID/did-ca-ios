/*
 * Copyright 2024-2025 OmniOne.
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
import CryptoKit
import DIDWalletSDK


/// for CA SDK
public class SDKUtils {
    
    public static func createWalletToken(purpose: WalletTokenPurposeEnum, userId: String) async throws -> String {
        // Request for Personalization + Wallet Lock Configuration Token Seed
        let parameter = try WalletAPI.shared.createWalletTokenSeed(purpose: purpose, pkgName: Bundle.main.bundleIdentifier!, userId: userId).toJsonData()
        
        let responseData = try await CommnunicationClient.doPost(url: URL(string: URLs.CAS_URL + "/cas/api/v1/request-wallet-tokendata")!, requestJsonData: parameter)
        
        let walletTokenData = try WalletTokenData.init(from: responseData)
        // certVcRef
        
        let resultNonce = try await WalletAPI.shared.createNonceForWalletToken(walletTokenData: walletTokenData, APIGatewayURL: URLs.API_URL)
        
        let digest = DigestUtils.getDigest(source: (try! walletTokenData.toJson()+resultNonce).data(using: String.Encoding.utf8)!, digestEnum: DigestEnum.sha256)
        // Hex
        let hWalletToken = String(MultibaseUtils.encode(type: MultibaseType.base16, data: digest).dropFirst())
        return hWalletToken
    }
    
    public func createServerToken(std: Data) async throws -> String {
        
        let serverTokenData = try ServerTokenData.init(from: std)
        try await self.verifyCertVc(serverTokenData: serverTokenData, roleType: RoleTypeEnum.Tas)
        
        let digest = DigestUtils.getDigest(source: std, digestEnum: DigestEnum.sha256)
        // Hex
        let hServerToken = String(MultibaseUtils.encode(type: MultibaseType.base64, data: digest))
        return hServerToken
    }
    
    public static func convertDateFormat(dateString: String) -> String? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        guard let date = dateFormatter.date(from: dateString) else {
            return nil
        }
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.string(from: date)
    }
    
    public static func convertDateFormat2(dateString: String) -> String? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ"
        guard let date = dateFormatter.date(from: dateString) else {
            return nil
        }
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.string(from: date)
    }

    
    public func verifyCertVc(serverTokenData: ServerTokenData, roleType: RoleTypeEnum) async throws {
        let did = serverTokenData.provider.did
        let url = serverTokenData.provider.certVcRef
        
        let certVcData = try await CommnunicationClient.doGet(url: URL(string: url)!)
        var certVc = try VerifiableCredential.init(from: certVcData)
        
        // DID comparison
        if did != certVc.credentialSubject.id {
            throw NSError(domain: "did matching fail", code: 1)
        }
        
        // Fetch CAS DIDDoc
        let didDocData = try await CommnunicationClient.doGet(url: URL(string: URLs.API_URL+"/api-gateway/api/v1/did-doc?did=" + certVc.issuer.id)!)
        let _didDoc = try DIDDocVO(from: didDocData)
        
        
        let didDoc = try DIDDocument(from: try MultibaseUtils.decode(encoded: _didDoc.didDoc))
        
        WalletLogger.shared.debug("didDoc: \(try didDoc.toJson(isPretty: true))")
        
        // check rule
        let schemaUrl = certVc.credentialSchema.id
        let schemaData = try await CommnunicationClient.doGet(url: URL(string: schemaUrl)!)
        
        let vcSchema = try VCSchema.init(from: schemaData)
        let vcSchemaClaims = vcSchema.credentialSubject.claims
        
        let certVcClaims = certVc.credentialSubject.claims
        
        var isExistValue = false
        
        for schemaClaim in vcSchemaClaims {
            for item in schemaClaim.items {
                if "role" == item.caption {
                    for certVcClaim in certVcClaims {
                        if certVcClaim.caption == item.caption {
                            print("rawValue: \(roleType.rawValue)")
                            if roleType.rawValue == certVcClaim.value {
                                isExistValue = true
                            }
                        }
                    }
                }
            }
        }
        
        if !isExistValue {
            throw NSError(domain: "role matching fail", code: 1)
        }
        
        
        // Membership credential VC signature verification
        for method in didDoc.verificationMethod {
            if method.id == "assert" {
                let pubKey = try MultibaseUtils.decode(encoded: method.publicKeyMultibase)
                let signature = try MultibaseUtils.decode(encoded: certVc.proof.proofValue!)
                certVc.proof.proofValue = nil
                certVc.proof.proofValueList = nil
                let digest = DigestUtils.getDigest(source: try certVc.toJsonData(), digestEnum: .sha256)
                let result = try WalletAPI.shared.verify(publicKey: pubKey, data: digest, signature: signature)
                print("certVcRef result: \(result)")
            }
        }
    }
    
    public static func generateMessageID() -> String {
        let currentDate = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMddHHmmssSSSSSS"
        let dateString = dateFormatter.string(from: currentDate)
        let randomHex = String(format: "%08X", arc4random_uniform(UINT32_MAX))
        let messageID = dateString + randomHex
        return messageID
    }
    
    public static func generateImg(base64String: String) throws -> UIImage {
        
        // Remove the prefix from the Base64 string
        let base64StringWithoutPrefix = base64String.replacingOccurrences(of: "data:image/png;base64,", with: "")
        if let imageData = Data(base64Encoded: base64StringWithoutPrefix, options: .ignoreUnknownCharacters) {
            // Convert a Data object to a UIImage object
            if let image = UIImage(data: imageData) {
                return image
            }
        } 
        throw NSError(domain: "generateImg error", code: 1)
    }
    
    public static func mergeNonce(clientNonce: Data?, serverNonce: Data?) throws -> Data {
        guard let clientNonce = clientNonce, let serverNonce = serverNonce else {
            throw NSError(domain: "mergeNonce error", code: 1)
        }
        
        var combinedData = Data()
        combinedData.append(clientNonce)
        combinedData.append(serverNonce)
        
        return DigestUtils.getDigest(source: combinedData, digestEnum: DigestEnum.sha256)
    }
    
    public static func mergeSharedSecretAndNonce(sharedSecret: Data, nonce: Data, symmetricCipherType: SymmetricCipherType) -> Data {
        
        var digest = Data()
        digest.append(sharedSecret)
        digest.append(nonce)
        
        let combinedResult = DigestUtils.getDigest(source: digest, digestEnum: DigestEnum.sha256)
        
        switch symmetricCipherType {
        case SymmetricCipherType.aes128CBC, SymmetricCipherType.aes128ECB:
            return combinedResult.prefix(16)
        case SymmetricCipherType.aes256CBC, SymmetricCipherType.aes256ECB:
            return combinedResult.prefix(32)
        @unknown default:
            fatalError()
        }
        
    }
    
    func generateRandomBytes() -> Data {
        var data = Data(count: 16)
        let result = data.withUnsafeMutableBytes { mutableBytes in
            mutableBytes.bindMemory(to: UInt8.self).baseAddress.map {
                for i in 0..<16 {
                    $0.advanced(by: i).pointee = UInt8(arc4random_uniform(256))
                }
                return true
            } ?? false
        }
        if !result {
            fatalError("Failed to generate random bytes")
        }
        return data
    }
}
