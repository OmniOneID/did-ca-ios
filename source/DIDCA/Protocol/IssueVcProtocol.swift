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


class IssueVcProtocol : CommonProtocol {
    
    public static let shared: IssueVcProtocol = {
        let instance = IssueVcProtocol()

        return instance
    }()
    
    @discardableResult
    private func proposeIssueVc(vcPlanId: String, issuer: String, offerId: String? = nil) async throws -> _ProposeIssueVc? {
        
        let parameter = try ProposeIssueVc(id: SDKUtils.generateMessageID(), vcPlanId: vcPlanId, issuer: issuer, offerId: offerId).toJsonData()
        if let responseData = try? await CommunicationClient.doPost(url: URL(string:URLs.TAS_URL+"/tas/api/v1/propose-issue-vc")!, requestJsonData: parameter) {
            
            let decodedResponse = try _ProposeIssueVc.init(from: responseData)

            super.txId = decodedResponse.txId
            self.refId = decodedResponse.refId

            return decodedResponse
        }
        throw NSError(domain: "proposeIssueVc error", code: 1)
    }
    
    
    private func requestIssueProfile() async throws {
        
        let parameter = try RequestIssueProfile(id: SDKUtils.generateMessageID(), txId: txId, serverToken: hServerToken).toJsonData()
        let responseData = try await CommunicationClient.doPost(url: URL(string: URLs.TAS_URL + "/tas/api/v1/request-issue-profile")!, requestJsonData: parameter)
        
        self.issueProfile = try _RequestIssueProfile.init(from: responseData)
        print("issue profile: \(try issueProfile!.toJson())")
        super.txId = issueProfile!.txId
    }
   
    @discardableResult
    private func requestIssueVc(passcode: String? = nil) async throws -> String {
        
        guard let didAuth = try WalletAPI.shared.getSignedDidAuth(authNonce: issueProfile!.authNonce, passcode: passcode) else {
            throw NSError(domain: "getDidAuth error", code: 1)
        }
        
        var vcId: String? = nil
        var issueVc: _RequestIssueVc? = nil
        
        (vcId, issueVc) = try await WalletAPI.shared.requestIssueVc(tasURL: URLs.TAS_URL + "/tas/api/v1/request-issue-vc",
                                                                       hWalletToken: self.hWalletToken,
                                                                       didAuth: didAuth,
                                                                       issuerProfile: issueProfile!,
                                                                       refId: refId,
                                                                       serverToken: hServerToken,
                                                                       APIGatewayURL: URLs.API_URL)
        super.txId = issueVc!.txId
        
        return vcId!
    }
    
    @discardableResult
    private func confirmIssueVc(vcId: String) async throws -> _ConfirmIssueVc {
        
        let parameter = try ConfirmIssueVc(id: SDKUtils.generateMessageID(), txId: super.txId, serverToken: hServerToken, vcId: vcId).toJsonData()
                
        let responseData = try await CommunicationClient.doPost(url: URL(string: URLs.TAS_URL + "/tas/api/v1/confirm-issue-vc")!, requestJsonData: parameter)
        
        let decodedResponse = try _ConfirmIssueVc.init(from: responseData)
            
        super.txId = decodedResponse.txId
        
        
        return decodedResponse
    }
    
    public func process(passcode: String? = nil) async throws -> _ConfirmIssueVc {
        
        let vcId = try await requestIssueVc(passcode: passcode)
        
        return try await confirmIssueVc(vcId: vcId)
    }
    
    public func preProcess(vcPlanId: String, issuer: String, offerId: String? = nil) async throws /*-> (String, String, String, _M210_RequestIssueProfile)*/ {
        
        self.reset()
        
        try await proposeIssueVc(vcPlanId: vcPlanId, issuer: issuer, offerId: offerId)
                
        let ecdh = try await super.requestEcdh(type: 1)
                
        let attestedAppInfo: AttestedAppInfo = try await super.requestAttestedAppInfo()
                    
        try await requestWalletTokenData(purpose: WalletTokenPurposeEnum.ISSUE_VC)
                    
        try await requestCreateToken(attestedAppInfo: attestedAppInfo, ecdh: ecdh, purpose: WalletTokenPurposeEnum.ISSUE_VC)
                        
        try await requestIssueProfile()
    }
}
