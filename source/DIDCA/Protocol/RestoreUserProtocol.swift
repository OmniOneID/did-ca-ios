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
        
        let parameter = try ProposeRestoreDidDoc(id: SDKUtils.generateMessageID(), offerId: offerId, did: did).toJsonData()
        if let data = try? await CommnunicationClient.doPost(url: URL(string:URLs.TAS_URL+"/tas/api/v1/propose-restore-diddoc")!, requestJsonData: parameter) {
            let proposeRestoreUser = try _ProposeRestoreDidDoc.init(from: data)
            super.txId = proposeRestoreUser.txId
            super.authNonce = proposeRestoreUser.authNonce
            // authNonce 저장 proposeRestoreUser.authNonce
            return proposeRestoreUser
        }
        
        throw NSError(domain: "proposeIssueVc error", code: 1)
    }

    @discardableResult
    private func requestRestoreUser(passcode: String? = nil) async throws -> _RequestRestoreDidDoc {

        guard let didAuth = try WalletAPI.shared.getSignedDidAuth(authNonce: super.authNonce, passcode: passcode) else {
            throw NSError(domain: "getDidAuth error", code: 1)
        }
        
        return try await WalletAPI.shared.requestRestoreUser(tasURL: URLs.TAS_URL + "/tas/api/v1/request-restore-diddoc", txId: super.txId, hWalletToken: super.hWalletToken, serverToken: super.hServerToken, didAuth: didAuth)
    }
    
    @discardableResult
    private func confirmRestoreUser(responseData: _RequestRestoreDidDoc) async throws -> _ConfirmRestoreDidDoc {
        
        let parameter = try ConfirmRegisterUser(id: SDKUtils.generateMessageID(), txId: responseData.txId, serverToken: super.hServerToken).toJsonData()
        let data = try await CommnunicationClient.doPost(url: URL(string: URLs.TAS_URL + "/tas/api/v1/confirm-restore-diddoc")!, requestJsonData: parameter)
        let confirmRegisterUser = try _ConfirmRestoreDidDoc(from: data)
        return confirmRegisterUser
    }
    

    
    @discardableResult
    public func process(passcode: String? = nil) async throws -> _ConfirmRestoreDidDoc {
        
        let regUserResponse = try await requestRestoreUser(passcode: passcode)
        
        return try await confirmRestoreUser(responseData: regUserResponse)
    }
    
    public func preProcess(offerId: String, did: String) async throws {
        
        try await proposeRestoreUser(offerId: offerId, did: did)
            
        let accEcdh = try await super.requestEcdh(type: 0)
                
        let attestedAppInfo: AttestedAppInfo = try await super.requestAttestedAppInfo()
        
        try await super.requestWalletTokenData(purpose: WalletTokenPurposeEnum.RESTORE_DID)
        
        try await super.requestCreateToken(attestedAppInfo: attestedAppInfo, ecdh: accEcdh, purpose: WalletTokenPurposeEnum.RESTORE_DID)
    }
}
