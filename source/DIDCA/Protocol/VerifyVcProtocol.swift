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


class VerifyVcProtocol: CommonProtocol {
    
    public static let shared: VerifyVcProtocol = {
        let instance = VerifyVcProtocol()

        return instance
    }()
    
    @discardableResult
    private func requestOffer() async throws -> VpOfferWrapper {
        
        let parameter = try RequestOfferPayload(mode: "Direct", device: "pc", service: "coupang", validSeconds: 1).toJsonData()
        let responseData = try await CommnunicationClient().doPost(url: URL(string:URLs.VERIFIER_URL+"/verifier/api/v1/request-offer-qr")!, requestJsonData: parameter)
            
        let decodedResponse = try VpOfferWrapper.init(from: responseData)
        print("\(decodedResponse)")
        super.txId = decodedResponse.txId!
        
        return decodedResponse
    }
    
    private func requestProfile(txId: String? = nil, offerId: String) async throws {
        
        let parameter = try RequestProfile(id: SDKUtils.generateMessageID(), offerId: offerId).toJsonData()
        
        let data = try await CommnunicationClient().doPost(url: URL(string:URLs.VERIFIER_URL+"/verifier/api/v1/request-profile")!, requestJsonData: parameter)
            
        self.verifyProfile = try _RequestProfile.init(from: data)
        
        print("vp profile: \(try verifyProfile!.toJson())")
        
        super.txId = verifyProfile!.txId
    }
    
    private func requestVerify(claimInfos: [ClaimInfo]? = nil, verifierProfile: _RequestProfile, passcode: String? = nil) async throws -> _RequestVerify {
        
        let (accE2e, encVp) = try await WalletAPI.shared.createEncVp(hWalletToken: hWalletToken, claimInfos: claimInfos, verifierProfile: verifierProfile, APIGatewayURL: URLs.API_URL, passcode: passcode)
            
        let parameter = try RequestVerify(id: SDKUtils.generateMessageID(),
                                               txId:super.txId,
                                               accE2e: accE2e,
                                               encVp: MultibaseUtils.encode(type: MultibaseType.base58BTC, data: encVp)).toJsonData()
        
        let data = try await CommnunicationClient().doPost(url: URL(string:URLs.VERIFIER_URL+"/verifier/api/v1/request-verify")!, requestJsonData: parameter)
        
        let decodedResponse = try _RequestVerify.init(from: data)
        
        super.txId = decodedResponse.txId
        
        return decodedResponse
    }
    
    
    public func process(hWalletToken: String, txId: String, claimInfos: [ClaimInfo]? = nil, verifierProfile: _RequestProfile, passcode: String? = nil) async throws {
        
        super.hWalletToken = hWalletToken
        super.txId = txId
        let _ = try await requestVerify(claimInfos: claimInfos, verifierProfile: verifierProfile, passcode:passcode)
    }
    
    public func preProcess(id: String? = nil, txId: String? = nil, offerId: String? = nil) async throws {
        
        try await requestProfile(txId: txId, offerId: offerId!)
        
        try await super.requestWalletTokenData(purpose: WalletTokenPurposeEnum.LIST_VC_AND_PRESENT_VP)
    }
}
