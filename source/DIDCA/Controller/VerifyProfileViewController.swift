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

import UIKit
import DIDWalletSDK

class VerifyProfileViewController: UIViewController {

    @IBOutlet weak var verifierLbl: UILabel!
    @IBOutlet weak var subjectLbl: UILabel!
    @IBOutlet weak var contentsTxtView: UITextView!
    
    @IBOutlet weak var submitBtn: UIButton!
    @IBOutlet weak var cancelBtn: UIButton!
    
    private var vpOffer: VerifyOfferPayload? = nil
    private var offerTxId: String? = nil
    
    private var vcSchemas : [Int : VCSchema] = [:]
    
    private var zkpSchemas : [String : ZKPCredentialSchema] = [:]
    private var zkpDefs : [String : ZKPCredentialDefinition] = [:]
    private var referentNameMap : [String : String] = [:]
    private var vcStatus: [String : VCStatusEnum] = [:]
    
    public func setVpOffer(vpOffer: VerifyOfferPayload)
    {
        self.vpOffer = vpOffer
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        if vpOffer!.type == .VerifyOffer
        {
            self.preProcessForVP()
        }
        else
        {
            self.preProcessForZKP()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    @IBAction func submitBtnAction(_ sender: Any)
    {
        
        if vpOffer!.type == .VerifyOffer
        {
            submitVP()
        }
        else
        {
            searchCredentials()
        }
    }
    
    @IBAction func cancelBtnAction(_ sender: Any) {
        
        DispatchQueue.main.async {
            self.dismiss(animated: false)
        }
    }
}
    
//MARK: Verifiable Presentation
extension VerifyProfileViewController
{
    func preProcessForVP()
    {
        
        ActivityUtil.show(vc: self){
            try await VerifyVcProtocol.shared.preProcess(id:SDKUtils.generateMessageID(),
                                                         txId: self.offerTxId,
                                                         offerId: self.vpOffer?.offerId )
        } completeClosure: {
            Task { @MainActor in
                
                let verifyProfile = VerifyVcProtocol.shared.verifyProfile!.profile
                self.verifierLbl.text = "The following certificate is submitted to the "+(verifyProfile.profile.verifier.name)
                
                self.subjectLbl.text = verifyProfile.title
                
//                let attributedString = NSMutableAttributedString()
                var textString = "Required information\n\n"
                
                let schemas = verifyProfile.profile.filter.credentialSchemas
                
                for index in 0 ..< schemas.count {
                    let schema = schemas[index]
                    print("schema: \(try schema.toJson())")
                    
                    let vcSchema : VCSchema = try await CommunicationClient.sendRequest(urlString: schema.id,
                                                                                        httpMethod: .GET)
                    
                    self.vcSchemas[index] = vcSchema
                    
                    let claimMap = vcSchema.credentialSubject.claims
                            .flatMap { claim in
                                claim.items.map { item in
                                    ("\(claim.namespace.id).\(item.id)", item.caption)
                                }
                            }
                            .reduce(into: [:]) { $0[$1.0] = $1.1 }
                    

                    for claim in schema.requiredClaims! {
                        textString.append(claimMap[claim]!)
                        textString.append("\n")
                    }
                }
                self.contentsTxtView.text = textString
                
                
            }
        } failureCloseClosure: { title, message in
            print("error title: \(title), message: \(message)")
            PopupUtils.showAlertPopup(title: title,
                                      content: message,
                                      VC: self) {
                self.dismiss(animated: true)
            }
        }
    }
    
    func submitVP()
    {
        SelectAuthHelper.show(on: self) { passcode in
            
            ActivityUtil.show(vc: self){
                if let vcs = try WalletAPI.shared.getAllCredentials(hWalletToken: VerifyVcProtocol.shared.getWalletToken()) {
                    
                    let schemas = VerifyVcProtocol.shared.verifyProfile!.profile.profile.filter.credentialSchemas
                    
                    
                    var claimInfos:[ClaimInfo] = .init()
                    
                    loop : for schema in schemas {
                        print("schema: \(try schema.toJson())")
                        
                        let filtered = vcs.filter { vc in
                            let isEqShema = vc.credentialSchema.id == schema.id
                            let isAllowedIssuer = schema.allowedIssuers?.contains(vc.issuer.id) ?? true
                            
                            return isEqShema && isAllowedIssuer
                        }.compactMap { vc in
                            if schema.presentAll ?? false {
                                let claims = vc.credentialSubject.claims.map { $0.code }
                                return ClaimInfo(credentialId: vc.id, claimCodes: claims)
                            }
                            else{
                                if let required = schema.requiredClaims{
                                    let claims = Set(vc.credentialSubject.claims.map { $0.code })
                                    if Set(required).isSubset(of: claims){
                                        return ClaimInfo(credentialId: vc.id, claimCodes: required)
                                    }
                                    else{
                                        return nil
                                    }
                                }
                                else{
                                    let claim = vc.credentialSubject.claims.first!.code
                                    return ClaimInfo(credentialId: vc.id, claimCodes: [claim])
                                }
                            }
                        }
                        if !filtered.isEmpty{
                            claimInfos.append(filtered.first!)
                            break loop
                        }
                    }
                    
                    if claimInfos.isEmpty{
                        throw NSError(domain: "Not found any claim", code: 1)
                    }
                    
                    try await VerifyVcProtocol().process(hWalletToken: VerifyVcProtocol.shared.getWalletToken(),txId: VerifyVcProtocol.shared.getTxId(), claimInfos: claimInfos, verifierProfile: VerifyVcProtocol.shared.getVerifyProfile()!, passcode: passcode)
                }
            } completeClosure: {
                self.moveToCompleteView()
            } failureCloseClosure: { title, message in
                PopupUtils.showAlertPopup(title: title,
                                          content: message,
                                          VC: self){
                    self.dismiss(animated: true)
                }
            }
        } cancelClosure: {
            PopupUtils.showAlertPopup(title: "Notification",
                                      content: "canceled by user",
                                      VC: self)
        }
    }
}

//MARK: Zero-Knowledge Proof
extension VerifyProfileViewController
{
    func extractDefsBy(proofRequest : ProofRequest) -> [String]
    {
        
        let attributeDefs = proofRequest.requestedAttributes?
            .values
            .flatMap { $0.restrictions.compactMap { $0["credDefId"] } } ?? []

        let predicatesDefs = proofRequest.requestedPredicates?
            .values
            .flatMap { $0.restrictions.compactMap { $0["credDefId"] } } ?? []
        
        return Array(Set(attributeDefs + predicatesDefs))
    }
    
    func retrieveDefsAndSchema(credDefIds : [String]) async throws
    {
        var schemaIds : Set<String> = []
        for credDefId in credDefIds
        {
            let def = try await CommunicationClient.getZKPCredentialDefinition(hostUrlString: URLs.API_URL,
                                                                                id: credDefId)
            schemaIds.insert(def.schemaId)
            zkpDefs[credDefId] = def
        }
        for schemaId in schemaIds {
            let schema = try await CommunicationClient.getZKPCredentialSchama(hostUrlString: URLs.API_URL,
                                                                               id: schemaId)
            zkpSchemas[schemaId] = schema
        }
    }
    
    func makeReferentNameMap()
    {
        referentNameMap = zkpSchemas.values.map {
            $0.attrTypes
                .flatMap { attr in
                    attr.items.map { item in
                        (attr.namespace.id + "." + item.label, item.caption)
                    }
                }
                .reduce(into: [String: String]()) { dict, pair in
                    dict[pair.0] = pair.1
                }
        }
        .reduce(into: [String: String]()) { result, dict in
            dict.forEach { key, value in
                result[key] = value
            }
        }
    }
    
    
    func preProcessForZKP()
    {
        ActivityUtil.show(vc: self){
            try await VerifyZKProofProtocol.shared.preProcess(id:SDKUtils.generateMessageID(),
                                                              txId: self.offerTxId,
                                                              offerId: self.vpOffer?.offerId )
        } completeClosure: {
            Task { @MainActor in
                
                let proofRequestProfile = VerifyZKProofProtocol.shared.proofRequestProfile!.proofRequestProfile
                
                self.verifierLbl.text = "The following certificate is submitted to the " + (proofRequestProfile.profile.verifier.name)
                                

                    
                self.subjectLbl.text = proofRequestProfile.title
                
                let proofRequest = proofRequestProfile.profile.proofRequest
                
                let defs = self.extractDefsBy(proofRequest: proofRequest)
                try await self.retrieveDefsAndSchema(credDefIds: defs)
                self.makeReferentNameMap()
                
                let attributeNames = proofRequest.requestedAttributes.map { $0.values.map { $0.name } } ?? []
                let predicatesNames = proofRequest.requestedPredicates.map { $0.values.map { $0.name } } ?? []
                
//                let attributedString = NSMutableAttributedString()
                var textString = "Required information\n\n"
                
//                attributedString.append(NSAttributedString(string: "Required information\n\n"))
                for name in Array(attributeNames + predicatesNames)
                {
                    let referentName = self.referentNameMap[name] ?? name
                    textString.append(referentName)
                    textString.append("\n")
//                    attributedString.append(NSAttributedString(string: referentName))
//                    attributedString.append(NSAttributedString(string: "\n"))
                }
//                self.contentsTxtView.attributedText = attributedString
                self.contentsTxtView.text = textString
            }
        } failureCloseClosure: { title, message in
            print("error title: \(title), message: \(message)")
            PopupUtils.showAlertPopup(title: title,
                                      content: message,
                                      VC: self){
                self.dismiss(animated: true)
            }
        }
    }
    
    func searchCredentials()
    {
        var availableReferent: AvailableReferent?
        ActivityUtil.show(vc: self){
            let proofRequest = VerifyZKProofProtocol.shared.proofRequestProfile?.proofRequestProfile.profile.proofRequest
            
            let hWalletToken = try await SDKUtils.createWalletToken(purpose: .PRESENT_VP, userId: Properties.getUserId()!)
            availableReferent = try WalletAPI.shared.searchZKPCredentials(hWalletToken: hWalletToken,
                                                                          proofRequest: proofRequest!)
        } completeClosure: {
            ActivityUtil.show(vc: self){
                let credIdSet: Set<String> = Set(
                    availableReferent!.attrReferent.flatMap { $0.referent }
                        .compactMap { $0.credId } +
                    availableReferent!.predicateReferent.flatMap { $0.referent }
                        .compactMap { $0.credId }
                )
                self.vcStatus = try await VCStatusGetter.getStatus(vcIds: Array(credIdSet))
                
                try self.checkReferentIsAvailable(attrReferent: availableReferent!.attrReferent)
                try self.checkReferentIsAvailable(attrReferent: availableReferent!.predicateReferent)
                
            } completeClosure: {
                
                
                self.moveToSubmissionView(availableReferent: availableReferent!)
            } failureCloseClosure: { title, message in
                PopupUtils.showAlertPopup(title: title,
                                          content: message,
                                          VC: self){
                    self.dismiss(animated: true)
                }
            }
        } failureCloseClosure: { title, message in
            PopupUtils.showAlertPopup(title: title,
                                      content: message,
                                      VC: self){
                self.dismiss(animated: true)
            }
        }
    }
    
    func checkReferentIsAvailable(attrReferent : [AttrReferent]) throws
    {
        for referent in attrReferent
        {
            let trues = Set(referent.referent.compactMap { self.vcStatus[$0.credId] == .ACTIVE })
            if trues.count != 2
            {
                if trues.first! == false
                {
                    throw NSError(domain: "No eligible attributes to submit", code: 1)
                }
            }
        }
    }
    
}

extension VerifyProfileViewController
{
    func moveToSubmissionView(availableReferent : AvailableReferent)
    {
        let submissionZKP = UIStoryboard.init(name: "ZKP", bundle: nil).instantiateViewController(withIdentifier: "ZKPSubmissionViewController") as! ZKPSubmissionViewController
        submissionZKP.availableReferent = availableReferent
        submissionZKP.zkpDefs = self.zkpDefs
        submissionZKP.zkpSchemas = self.zkpSchemas
        submissionZKP.referentNameMap = self.referentNameMap
        submissionZKP.vcStatus = self.vcStatus
//        submissionZKP.modalPresentationStyle = .fullScreen
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1)
        {
            self.navigationController?.pushViewController(submissionZKP, animated: false)
        }
    }
    
    func moveToCompleteView()
    {
        let verifyCompletedVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "VerifyCompletedViewController") as! VerifyCompletedViewController
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.navigationController?.pushViewController(verifyCompletedVC, animated: false)
        }
    }
}
