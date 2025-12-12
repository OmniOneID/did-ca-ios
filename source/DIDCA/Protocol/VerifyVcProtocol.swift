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

class VerifyVcProtocol: CommonProtocol {
    
    public static let shared: VerifyVcProtocol = {
        let instance = VerifyVcProtocol()

        return instance
    }()
    
    private func requestProfile(txId: String? = nil, offerId: String) async throws {
        
        let parameter = RequestProfile(id: SDKUtils.generateMessageID(),
                                       offerId: offerId)
        
        let urlString = URLs.VERIFIER_URL+"/verifier/api/v1/request-profile"
        
        self.verifyProfile = try await CommunicationClient.sendRequest(urlString: urlString,
                                                                       requestJsonable: parameter)
        
        print("vp profile: \(try verifyProfile!.toJson())")
        
        super.txId = verifyProfile!.txId
    }
    
    @discardableResult
    private func requestVerify(claimInfos: [ClaimInfo]? = nil,
                               verifierProfile: _RequestProfile,
                               passcode: String? = nil) async throws -> _RequestVerify {
        
        let (accE2e, encVp) = try await WalletAPI.shared.createEncVp(hWalletToken: hWalletToken,
                                                                     claimInfos: claimInfos,
                                                                     verifierProfile: verifierProfile,
                                                                     APIGatewayURL: URLs.API_URL,
                                                                     passcode: passcode)
            
        let parameter = RequestVerify(
            id: SDKUtils.generateMessageID(),
            txId:super.txId,
            accE2e: accE2e,
            encVp: MultibaseUtils.encode(type: .base58BTC,
                                         data: encVp)
        )
        
        let urlString = URLs.VERIFIER_URL+"/verifier/api/v1/request-verify"
        
        let decodedResponse : _RequestVerify = try await CommunicationClient.sendRequest(urlString: urlString,
                                                                                         requestJsonable: parameter)
        super.txId = decodedResponse.txId
        
        return decodedResponse
    }
    
    
    public func process(hWalletToken: String, txId: String, claimInfos: [ClaimInfo]? = nil, verifierProfile: _RequestProfile, passcode: String? = nil) async throws {
        
        super.hWalletToken = hWalletToken
        super.txId = txId
        try await requestVerify(claimInfos: claimInfos, verifierProfile: verifierProfile, passcode:passcode)
    }
    
    public func preProcess(id: String? = nil, txId: String? = nil, offerId: String? = nil) async throws {
        
        self.reset()
        
        try await requestProfile(txId: txId, offerId: offerId!)
        
        try await super.requestWalletTokenData(purpose: WalletTokenPurposeEnum.LIST_VC_AND_PRESENT_VP)
    }
}
