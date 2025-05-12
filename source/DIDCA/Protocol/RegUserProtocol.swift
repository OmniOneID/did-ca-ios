/*
 * Copyright 2024 OmniOne.
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


class RegUserProtocol: CommonProtocol {
    public static let shared: RegUserProtocol = {
        let instance = RegUserProtocol()
        return instance
    }()
    
    @discardableResult
    private func proposeRegisterUser() async throws -> _ProposeRegisterUser? {
        
        let parameter = try ProposeRegisterUser(id: SDKUtils.generateMessageID()).toJsonData()
        if let data = try? await CommnunicationClient().doPost(url: URL(string:URLs.TAS_URL+"/tas/api/v1/propose-register-user")!, requestJsonData: parameter) {
            let proposeRegisterUser = try _ProposeRegisterUser.init(from: data)
            super.txId = proposeRegisterUser.txId
            
            return proposeRegisterUser
        }
        
        throw NSError(domain: "proposeIssueVc error", code: 1)
    }

    private func requestRegisterUser(signedDidDoc: SignedDIDDoc) async throws -> _RequestRegisterUser {

        return try await WalletAPI.shared.requestRegisterUser(tasURL: URLs.TAS_URL + "/tas/api/v1/request-register-user", txId: super.txId, hWalletToken: super.hWalletToken, serverToken: super.hServerToken, signedDIDDoc: signedDidDoc)
    }
    
    private func confirmRegisterUser(responseData: _RequestRegisterUser) async throws -> _ConfirmRegisterUser {
        
        let parameter = try ConfirmRegisterUser(id: SDKUtils.generateMessageID(), txId: responseData.txId, serverToken: super.hServerToken).toJsonData()
        let data = try await CommnunicationClient().doPost(url: URL(string: URLs.TAS_URL + "/tas/api/v1/confirm-register-user")!, requestJsonData: parameter)
        let confirmRegisterUser = try _ConfirmRegisterUser(from: data)
        return confirmRegisterUser
    }
    
    private func retrieveKyc() async throws -> _RetrieveKyc {
        
        let parameter = try RetrieveKyc(id: SDKUtils.generateMessageID(), txId: txId, serverToken: hServerToken, kycTxId: Properties.getUserId()!).toJsonData()
        let data = try await CommnunicationClient().doPost(url: URL(string: URLs.TAS_URL + "/tas/api/v1/retrieve-kyc")!, requestJsonData: parameter)
        
        return try _RetrieveKyc(from: data)
    }
    
    public func process(signedDidDoc: SignedDIDDoc) async throws -> _ConfirmRegisterUser {
        
        let regUserResponse = try await requestRegisterUser(signedDidDoc: signedDidDoc)
        
        return try await confirmRegisterUser(responseData: regUserResponse)
    }
    
    public func preProcess() async throws {
        
        try await proposeRegisterUser()
            
        let accEcdh = try await super.requestEcdh(type: 0)
                
        let attestedAppInfo: AttestedAppInfo = try await super.requestAttestedAppInfo()
        
        try await super.requestWalletTokenData(purpose: WalletTokenPurposeEnum.CREATE_DID)
        
        try await super.requestCreateToken(attestedAppInfo: attestedAppInfo, ecdh: accEcdh, purpose: WalletTokenPurposeEnum.CREATE_DID)
        
        try await retrieveKyc()
    }
}
