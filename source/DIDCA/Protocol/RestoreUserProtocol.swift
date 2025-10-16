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



class RestoreUserProtocol: CommonProtocol {
    public static let shared: RestoreUserProtocol = {
        let instance = RestoreUserProtocol()

        return instance
    }()
    
    @discardableResult
    private func proposeRestoreUser(offerId: String, did: String) async throws -> _ProposeRestoreDidDoc {
        
        let parameter = ProposeRestoreDidDoc(id: SDKUtils.generateMessageID(),
                                             offerId: offerId,
                                             did: did)
        
        let urlString = URLs.TAS_URL+"/tas/api/v1/propose-restore-diddoc"
        
        let proposeRestoreUser : _ProposeRestoreDidDoc = try await CommunicationClient.sendRequest(urlString: urlString,
                                                                                                   requestJsonable: parameter)
        super.txId = proposeRestoreUser.txId
        super.authNonce = proposeRestoreUser.authNonce

        return proposeRestoreUser
    }

    @discardableResult
    private func requestRestoreUser(passcode: String? = nil) async throws -> _RequestRestoreDidDoc {

        let didAuth = try WalletAPI.shared.getSignedDidAuth(authNonce: super.authNonce,
                                                            passcode: passcode)
        
        return try await WalletAPI.shared.requestRestoreUser(tasURL: URLs.TAS_URL + "/tas/api/v1/request-restore-diddoc",
                                                             txId: super.txId,
                                                             hWalletToken: super.hWalletToken,
                                                             serverToken: super.hServerToken,
                                                             didAuth: didAuth)
    }
    
    @discardableResult
    private func confirmRestoreUser(responseData: _RequestRestoreDidDoc) async throws -> _ConfirmRestoreDidDoc {
        
        let parameter = ConfirmRegisterUser(id: SDKUtils.generateMessageID(),
                                            txId: responseData.txId,
                                            serverToken: super.hServerToken)
        
        let urlString = URLs.TAS_URL + "/tas/api/v1/confirm-restore-diddoc"
        
        return try await CommunicationClient.sendRequest(urlString: urlString,
                                                         requestJsonable: parameter)
    }
    

    
    @discardableResult
    public func process(passcode: String? = nil) async throws -> _ConfirmRestoreDidDoc {
        
        let regUserResponse = try await requestRestoreUser(passcode: passcode)
        
        return try await confirmRestoreUser(responseData: regUserResponse)
    }
    
    public func preProcess(offerId: String, did: String) async throws {
        
        try await proposeRestoreUser(offerId: offerId, did: did)
            
        let accEcdh = try await super.requestEcdh(type: .DeviceDidDocument)
                
        let attestedAppInfo: AttestedAppInfo = try await super.requestAttestedAppInfo()
        
        try await super.requestWalletTokenData(purpose: WalletTokenPurposeEnum.RESTORE_DID)
        
        try await super.requestCreateToken(attestedAppInfo: attestedAppInfo, ecdh: accEcdh, purpose: WalletTokenPurposeEnum.RESTORE_DID)
    }
}
