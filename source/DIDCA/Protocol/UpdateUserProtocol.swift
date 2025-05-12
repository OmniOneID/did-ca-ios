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



class UpdateUserProtocol: CommonProtocol {
    public static let shared: UpdateUserProtocol = {
        let instance = UpdateUserProtocol()

        return instance
    }()
    
    @discardableResult
    private func proposeUpdateUser(did: String) async throws -> _ProposeUpdateDidDoc {
        
        let parameter = try ProposeUpdateDidDoc(id: SDKUtils.generateMessageID(), did: did).toJsonData()
        if let data = try? await CommnunicationClient().doPost(url: URL(string:URLs.TAS_URL+"/tas/api/v1/propose-update-diddoc")!, requestJsonData: parameter) {
            let proposeUpdateDidDoc = try _ProposeUpdateDidDoc.init(from: data)
            super.txId = proposeUpdateDidDoc.txId
            super.authNonce = proposeUpdateDidDoc.authNonce
            return proposeUpdateDidDoc
        }
        
        throw NSError(domain: "proposeUpdateDidDoc error", code: 1)
    }

    @discardableResult
    private func requestUpdateUser(passcode: String? = nil, signedDidDoc: SignedDIDDoc) async throws -> _RequestUpdateDidDoc {

        guard let didAuth = try WalletAPI.shared.getSignedDidAuth(authNonce: super.authNonce, passcode: passcode) else {
            throw NSError(domain: "getDidAuth error", code: 1)
        }
        
        return try await WalletAPI.shared.requestUpdateUser(tasURL: URLs.TAS_URL + "/tas/api/v1/request-update-diddoc", txId: super.txId, hWalletToken: super.hWalletToken, serverToken: super.hServerToken, didAuth: didAuth, signedDIDDoc: signedDidDoc)
    }
    
    @discardableResult
    private func confirmUpdateUser(responseData: _RequestUpdateDidDoc) async throws -> _ConfirmUpdateDidDoc {
        
        let parameter = try ConfirmUpdateDidDoc(id: SDKUtils.generateMessageID(), txId: responseData.txId, serverToken: super.hServerToken).toJsonData()
        let data = try await CommnunicationClient().doPost(url: URL(string: URLs.TAS_URL + "/tas/api/v1/confirm-update-diddoc")!, requestJsonData: parameter)
        let confirmUpdateUser = try _ConfirmUpdateDidDoc(from: data)
        return confirmUpdateUser
    }
        
    @discardableResult
    public func process(passcode: String? = nil, signedDidDoc: SignedDIDDoc) async throws -> _ConfirmUpdateDidDoc {
        
        let regUpdateUserResponse = try await requestUpdateUser(passcode: passcode, signedDidDoc: signedDidDoc)
        
        return try await confirmUpdateUser(responseData: regUpdateUserResponse)
    }
    
    public func preProcess(did: String) async throws {
        
        try await proposeUpdateUser(did: did)
            
        let accEcdh = try await super.requestEcdh(type: 0)
                
        let attestedAppInfo: AttestedAppInfo = try await super.requestAttestedAppInfo()
        
        try await super.requestWalletTokenData(purpose: WalletTokenPurposeEnum.UPDATE_DID)
        
        try await super.requestCreateToken(attestedAppInfo: attestedAppInfo, ecdh: accEcdh, purpose: WalletTokenPurposeEnum.UPDATE_DID)
    }
}
