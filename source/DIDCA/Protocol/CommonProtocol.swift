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

import Foundation
import DIDWalletSDK

class CommonProtocol {
    // 
    internal var txId: String = ""
    internal var refId: String = ""
    internal var issueProfile: _RequestIssueProfile?
    internal var verifyProfile: _RequestProfile?
    internal var proofRequestProfile: _RequestProofRequestProfile?
    internal var hServerToken: String = ""
    internal var hWalletToken: String = ""
    internal var clientNonce: String = ""
    internal var priKey: String = ""
    internal var requestCreateToken: _RequestCreateToken?
    internal var issuerNonce: String = ""
    internal var authType: VerifyAuthType = .init(rawValue: 6)
    internal var vcId: String = ""
    internal var authNonce: String = ""
    
    public func reset() -> Void {
        self.txId = ""
        self.refId = ""
        self.issueProfile = nil
        self.verifyProfile = nil
        self.proofRequestProfile = nil
        self.hServerToken = ""
        self.hWalletToken = ""
        self.clientNonce = ""
        self.priKey = ""
        self.requestCreateToken = nil
        self.issuerNonce = ""
        self.vcId = ""
        self.authNonce = ""
    }
    
    public func getAuthNOnce() -> String {
        self.authNonce
    }
    
    public func getAuthType() -> VerifyAuthType {
        self.authType
    }
    
    public func getTxId() -> String {
        return self.txId
    }
    
    public func getRefId() -> String {
        return self.refId
    }
    
    public func getVerifyProfile() -> _RequestProfile? {
        return self.verifyProfile
    }
    
    public func getProofRequestProfile() -> _RequestProofRequestProfile? {
        return self.proofRequestProfile
    }
    
    public func getIssueProfile() -> _RequestIssueProfile? {
        return self.issueProfile
    }
    
    public func getServerToken() -> String {
        return self.hServerToken
    }
    
    public func getWalletToken() -> String {
        return self.hWalletToken
    }
    
    @discardableResult
    internal func requestEcdh(type: DidDocumentType) async throws -> _RequestEcdh {
        
        let nonce = try CryptoUtils.generateNonce(size: 16)
        let clientNonce = MultibaseUtils.encode(type: .base58BTC,
                                                data: nonce)
        
        self.clientNonce = clientNonce
        
        let keyPair = try CryptoUtils.generateECKeyPair(ecType: .secp256r1)
        self.priKey = MultibaseUtils.encode(type: .base58BTC,
                                            data: keyPair.privateKey)
        
        let didDoc = try WalletAPI.shared.getDidDocument(type: type)
        
        let proofType = didDoc.id + "?versionId=" + didDoc.versionId + "#keyagree"
        let clientType = didDoc.id
        
        var reqEcdh: ReqEcdh = ReqEcdhBuilder()
            .setClient(clientType)   // Wallet DID
            .setClientNonce(clientNonce)
            .setPublicKey(MultibaseUtils.encode(type: .base58BTC,
                                                data: keyPair.publicKey) )
            .setCurve(.secp256r1)
            .setProof(Proof(created: Date.getUTC0Date(seconds: 0),
                            proofPurpose: .keyAgreement,
                            verificationMethod: proofType,
                            type: .secp256r1Signature2018))
            .build()
        let source = try DigestUtils.getDigest(source: reqEcdh.toJsonData(),
                                               digestEnum: .sha256)
        
        // (core func)
        let signature = try WalletAPI.shared.sign(keyId: KeyIds.keyagree, data: source, type: type)
        
        reqEcdh.proof?.proofValue = MultibaseUtils.encode(type: .base58BTC, data: signature)
        print("sig: \(String(describing: reqEcdh.proof?.proofValue)))")
        
        let request = RequestEcdh(id: SDKUtils.generateMessageID(), txId: txId, reqEcdh: reqEcdh)
        
        let urlString = URLs.TAS_URL + "/tas/api/v1/request-ecdh"
        let accEcdh : _RequestEcdh = try await CommunicationClient.sendRequest(urlString: urlString,
                                                                               requestJsonable: request)
        return accEcdh
    }
    
    internal func requestWalletTokenData(purpose: WalletTokenPurposeEnum) async throws {
        self.hWalletToken = try await SDKUtils.createWalletToken(purpose: purpose, userId: Properties.getUserId()!)
    }
    
    // To generate server token seeds
    internal func requestAttestedAppInfo() async throws -> AttestedAppInfo {
        
        let requestAttestedAppInfo = RequestAttestedAppInfo(appId: Properties.getCaAppId()!)
        
        let urlString = URLs.CAS_URL + "/cas/api/v1/request-attested-appinfo"
        
        let attested : AttestedAppInfo = try await CommunicationClient.sendRequest(urlString: urlString,
                                                                                   requestJsonable: requestAttestedAppInfo)
        return attested
    }
    
    @discardableResult
    internal func requestCreateToken(attestedAppInfo: AttestedAppInfo, ecdh: _RequestEcdh, purpose: WalletTokenPurposeEnum) async throws -> _RequestCreateToken {
        
        let walletInfo = try WalletAPI.shared.getSignedWalletInfo()
        let seed = ServerTokenSeed(purpose: purpose, walletInfo: walletInfo, attestedAppInfo: attestedAppInfo)
        
        let request = RequestCreateToken(id: SDKUtils.generateMessageID(),
                                         txId: txId,
                                         seed: seed)
        
        let urlString = URLs.TAS_URL + "/tas/api/v1/request-create-token"
        
        let requestCreateToken : _RequestCreateToken = try await CommunicationClient.sendRequest(urlString: urlString,
                                                                                                 requestJsonable: request)

        // Generate server token data
        let encStd = try MultibaseUtils.decode(encoded: requestCreateToken.encStd)
        
        let clientNonce = try MultibaseUtils.decode(encoded: self.clientNonce)
        let serverNonce = try MultibaseUtils.decode(encoded: ecdh.accEcdh.serverNonce)
        let mergedNonce = try SDKUtils.mergeNonce(clientNonce: clientNonce, serverNonce: serverNonce)
        
        
        print("clientNonce: \(MultibaseUtils.encode(type: MultibaseType.base58BTC, data: clientNonce))")
        print("mergedNonce: \(MultibaseUtils.encode(type: MultibaseType.base58BTC, data: mergedNonce))")
        
        // Generate session key
        let secretKey = try CryptoUtils.generateSharedSecret(ecType: ECType.secp256r1, privateKey: MultibaseUtils.decode(encoded: self.priKey), publicKey: MultibaseUtils.decode(encoded: ecdh.accEcdh.publicKey))
        
        print("ecdh.accEcdh.publicKey: \(ecdh.accEcdh.publicKey)")
        print("secretKey: \(MultibaseUtils.encode(type: MultibaseType.base58BTC, data: secretKey))")
        
        let clientMergedSharedSecret = SDKUtils.mergeSharedSecretAndNonce(sharedSecret: secretKey, nonce: mergedNonce, symmetricCipherType: SymmetricCipherType.aes256CBC)
    
        print("clientMergedSharedSecret: \(MultibaseUtils.encode(type: MultibaseType.base58BTC, data: clientMergedSharedSecret))")
        
        let iv = try MultibaseUtils.decode(encoded: requestCreateToken.iv)
        
        // AES decryption (tmp)
        let std = try CryptoUtils.decrypt(cipher: encStd, info: CipherInfo(cipherType: .aes256CBC, padding: .pkcs5), key: clientMergedSharedSecret, iv: iv)
        
        self.hServerToken = try await SDKUtils().createServerToken(std: std)
        
        return requestCreateToken
    }
}
