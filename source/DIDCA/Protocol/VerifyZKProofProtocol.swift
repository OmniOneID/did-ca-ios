//
/*
 * Copyright 2025 OmniOne.
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

class VerifyZKProofProtocol: CommonProtocol {
    
    public static let shared: VerifyZKProofProtocol = {
        let instance = VerifyZKProofProtocol()

        return instance
    }()
    
    private func requestProfile(txId: String? = nil, offerId: String) async throws {
        
        let parameter = RequestProfile(id: SDKUtils.generateMessageID(),
                                       offerId: offerId)
        
        let urlString = URLs.VERIFIER_URL+"/verifier/api/v1/request-proof-request-profile"
        
        self.proofRequestProfile = try await CommunicationClient.sendRequest(urlString: urlString,
                                                                             requestJsonable: parameter)
        print("proof request profile: \(try proofRequestProfile!.toJson())")
        
        super.txId = proofRequestProfile!.txId
    }
    
    @discardableResult
    private func requestVerify(selectedReferents : [UserReferent],
                               proofParam: ZKProofParam,
                               proofRequestProfile: _RequestProofRequestProfile) async throws -> _RequestVerify {
        
        let (accE2e, encProof) = try await WalletAPI.shared.createEncZKProof(hWalletToken: hWalletToken,
                                                                          selectedReferents: selectedReferents,
                                                                          proofParam: proofParam,
                                                                          proofRequestProfile: proofRequestProfile,
                                                                          APIGatewayURL: URLs.API_URL)
            
        let parameter = RequestZKPVerify(
            id: SDKUtils.generateMessageID(),
            txId:super.txId,
            accE2e: accE2e,
            encProof: MultibaseUtils.encode(type: .base64,
                                            data: encProof),
            nonce: proofRequestProfile.proofRequestProfile.profile.proofRequest.nonce
        )
        
        let urlString = URLs.VERIFIER_URL+"/verifier/api/v1/request-verify-proof"
        
        let response : _RequestVerify = try await CommunicationClient.sendRequest(urlString: urlString,
                                                                                  requestJsonable: parameter)
        super.txId = response.txId
        
        return response
    }
    
    public func process(hWalletToken: String,
                        txId: String,
                        selectedReferents : [UserReferent],
                        proofParam: ZKProofParam,
                        proofRequestProfile: _RequestProofRequestProfile) async throws {
        
        super.hWalletToken = hWalletToken
        super.txId = txId
        
        try await requestVerify(selectedReferents: selectedReferents,
                                proofParam: proofParam,
                                proofRequestProfile: proofRequestProfile)
    }
    
    public func preProcess(id: String? = nil, txId: String? = nil, offerId: String? = nil) async throws {
        
        self.reset()
        
        try await requestProfile(txId: txId, offerId: offerId!)
        
        try await super.requestWalletTokenData(purpose: WalletTokenPurposeEnum.LIST_VC_AND_PRESENT_VP)
    }
}
