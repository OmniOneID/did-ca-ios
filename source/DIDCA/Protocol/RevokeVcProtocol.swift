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



class RevokeVcProtocol : CommonProtocol {
    public static let shared: RevokeVcProtocol = {
        let instance = RevokeVcProtocol()
        return instance
    }()
    
    @discardableResult
    private func proposeRevokeVc(vcId: String) async throws -> _ProposeRevokeVc? {
        
        let parameter = try ProposeRevokeVc(id: SDKUtils.generateMessageID(), vcId: vcId).toJsonData()
        if let responseData = try? await CommnunicationClient.doPost(url: URL(string:URLs.TAS_URL+"/tas/api/v1/propose-revoke-vc")!, requestJsonData: parameter) {
            
            let decodedResponse = try _ProposeRevokeVc.init(from: responseData)
            super.vcId = vcId
            super.txId = decodedResponse.txId
            super.issuerNonce = decodedResponse.issuerNonce
            super.authType = decodedResponse.authType
            
            return decodedResponse
        }
        throw NSError(domain: "proposeRevokeVc error", code: 1)
    }
   
    @discardableResult
    private func requestRevokeVc(authType: VerifyAuthType, passcode: String? = nil) async throws -> _RequestRevokeVc {
        
        let revokeVc = try await WalletAPI.shared.requestRevokeVc(hWalletToken: self.hWalletToken,
                                                                tasURL: URLs.TAS_URL + "/tas/api/v1/request-revoke-vc",
                                                                authType: authType,
                                                                vcId: super.vcId,
                                                                issuerNonce: super.issuerNonce,
                                                                txId: super.txId,
                                                                serverToken: self.hServerToken,
                                                                passcode: passcode)
        super.txId = revokeVc.txId
        return revokeVc
    }
    
    @discardableResult
    private func confirmRevokeVc(txId: String) async throws -> _ConfirmRevokeVc {
        
        let parameter = try ConfirmRevokeVc(id: SDKUtils.generateMessageID(), txId: txId, serverToken: super.hServerToken).toJsonData()
                
        let responseData = try await CommnunicationClient.doPost(url: URL(string: URLs.TAS_URL + "/tas/api/v1/confirm-revoke-vc")!, requestJsonData: parameter)
        
        let decodedResponse = try _ConfirmRevokeVc.init(from: responseData)
            
        super.txId = decodedResponse.txId
        
        let result = try WalletAPI.shared.deleteCredentials(hWalletToken: self.hWalletToken, ids: [super.vcId])
        print("delete result: \(result)")
        
        return decodedResponse
    }
    
    public func process(passcode: String? = nil) async throws -> _ConfirmRevokeVc {
        
        let response = try await requestRevokeVc(authType: super.authType, passcode: passcode)
        
        return try await confirmRevokeVc(txId: response.txId)
    }
    
    public func preProcess(vcId: String) async throws {
        
        try await proposeRevokeVc(vcId: vcId)
                
        let ecdh = try await super.requestEcdh(type: 1)
                
        let attestedAppInfo: AttestedAppInfo = try await super.requestAttestedAppInfo()
                    
        try await requestWalletTokenData(purpose: WalletTokenPurposeEnum.REMOVE_VC)
                    
        try await requestCreateToken(attestedAppInfo: attestedAppInfo, ecdh: ecdh, purpose: WalletTokenPurposeEnum.REMOVE_VC)
    }
}
