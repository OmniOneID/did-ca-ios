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


class RegUserProtocol: CommonProtocol {
    public static let shared: RegUserProtocol = {
        let instance = RegUserProtocol()
        return instance
    }()
    
    @discardableResult
    private func proposeRegisterUser() async throws -> _ProposeRegisterUser
    {
        let parameter = ProposeRegisterUser(id: SDKUtils.generateMessageID())
        
        let urlString = URLs.TAS_URL+"/tas/api/v1/propose-register-user"
        let proposeRegisterUser: _ProposeRegisterUser = try await CommunicationClient.sendRequest(urlString:urlString,
                                                                                                  requestJsonable: parameter)
        super.txId = proposeRegisterUser.txId
        return proposeRegisterUser
    }

    private func requestRegisterUser(signedDidDoc: SignedDIDDoc) async throws -> _RequestRegisterUser {

        return try await WalletAPI.shared.requestRegisterUser(tasURL: URLs.TAS_URL + "/tas/api/v1/request-register-user", txId: super.txId, hWalletToken: super.hWalletToken, serverToken: super.hServerToken, signedDIDDoc: signedDidDoc)
    }
    
    private func confirmRegisterUser(responseData: _RequestRegisterUser) async throws -> _ConfirmRegisterUser {
        
        let parameter = ConfirmRegisterUser(id: SDKUtils.generateMessageID(),
                                            txId: responseData.txId,
                                            serverToken: super.hServerToken)
        
        let urlString = URLs.TAS_URL + "/tas/api/v1/confirm-register-user"
        let confirmRegisterUser: _ConfirmRegisterUser = try await CommunicationClient.sendRequest(urlString:urlString,
                                                                                                  requestJsonable: parameter)
        return confirmRegisterUser
    }
    
    @discardableResult
    private func retrieveKyc() async throws -> _RetrieveKyc {
        
        let parameter = RetrieveKyc(id: SDKUtils.generateMessageID(),
                                    txId: txId,
                                    serverToken: hServerToken,
                                    kycTxId: Properties.getUserId()!,
                                    kycToken: nil)
        
        let urlString = URLs.TAS_URL + "/tas/api/v1/retrieve-kyc"
        
        let retrieveKyc: _RetrieveKyc = try await CommunicationClient.sendRequest(urlString:urlString,
                                                                                  requestJsonable: parameter)
        return retrieveKyc
    }
    
    @discardableResult
    public func process(signedDidDoc: SignedDIDDoc) async throws -> _ConfirmRegisterUser
    {
        
        let regUserResponse = try await requestRegisterUser(signedDidDoc: signedDidDoc)
        
        let result = try await confirmRegisterUser(responseData: regUserResponse)
        
        try WalletAPI.shared.saveHolderDIDDocument()
        
        return result
    }
    
    public func preProcess() async throws {
        
        try await proposeRegisterUser()
            
        let accEcdh = try await super.requestEcdh(type: .DeviceDidDocument)
                
        let attestedAppInfo: AttestedAppInfo = try await super.requestAttestedAppInfo()
        
        try await super.requestWalletTokenData(purpose: WalletTokenPurposeEnum.CREATE_DID)
        
        try await super.requestCreateToken(attestedAppInfo: attestedAppInfo, ecdh: accEcdh, purpose: WalletTokenPurposeEnum.CREATE_DID)
        
        try await retrieveKyc()
    }
}
