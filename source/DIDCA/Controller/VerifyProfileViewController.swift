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
import UIKit



import DIDWalletSDK


class VerifyProfileViewController: UIViewController {

    @IBOutlet weak var verifierLbl: UILabel!
    @IBOutlet weak var issuanceDateLbl: UILabel!
    @IBOutlet weak var subjectLbl: UILabel!
    @IBOutlet weak var contentsTxtView: UITextView!
    
    @IBOutlet weak var submitBtn: UIButton!
    @IBOutlet weak var cancelBtn: UIButton!
    
    private var vpOffer: VerifyOfferPayload? = nil
    private var offerTxId: String? = nil
    
    @IBAction func submitBtnAction(_ sender: Any) {
        
        do {
            try WalletAPI.shared.getKeyInfos(ids: ["pin","bio"])
            
            let selectAuthVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "SelectAuthViewController") as! SelectAuthViewController
            selectAuthVC.setCommandType(command: 1)
            selectAuthVC.modalPresentationStyle = .fullScreen
            DispatchQueue.main.async { self.present(selectAuthVC, animated: false, completion: nil) }
        } catch {
            let pinVC = UIStoryboard.init(name: "PIN", bundle: nil).instantiateViewController(withIdentifier: "PincodeViewController") as! PincodeViewController
            pinVC.modalPresentationStyle = .fullScreen
            pinVC.setRequestType(type: PinCodeTypeEnum.PIN_CODE_AUTHENTICATION_SIGNATURE_TYPE)
            pinVC.confirmButtonCompleteClosure = { [self] passcode in
                Task { @MainActor in
                    do {
                        if let vcs = try WalletAPI.shared.getAllCrentials(hWalletToken: VerifyVcProtocol.shared.getWalletToken()) {
                            
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
                                PopupUtils.showAlertPopup(title: "Insufficient claim", content: "Not found any claim", VC: self)
                                return
                            }
                            
                            try await VerifyVcProtocol().process(hWalletToken: VerifyVcProtocol.shared.getWalletToken(),txId: VerifyVcProtocol.shared.getTxId(), claimInfos: claimInfos, verifierProfile: VerifyVcProtocol.shared.getVerifyProfile()!, passcode: passcode)
                            
                            let verifyCompletedVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "VerifyCompletedViewController") as! VerifyCompletedViewController
                            verifyCompletedVC.modalPresentationStyle = .fullScreen
                            DispatchQueue.main.async {
                                self.present(verifyCompletedVC, animated: false, completion: nil)
                            }
                        }
                    } catch let error as WalletSDKError {
                        print("error code: \(error.code), message: \(error.message)")
                        PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
                    } catch let error as WalletCoreError {
                        print("error code: \(error.code), message: \(error.message)")
                        PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
                    } catch let error as CommunicationSDKError {
                        print("error code: \(error.code), message: \(error.message)")
                        PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
                    }
                }
            }
            pinVC.cancelButtonCompleteClosure = { 
                PopupUtils.showAlertPopup(title: "Notification", content: "canceled by user", VC: self)
            }
            DispatchQueue.main.async { self.present(pinVC, animated: false, completion: nil) }
        }
    }
    
    @IBAction func cancelBtnAction(_ sender: Any) {
        DispatchQueue.main.async {
            self.dismiss(animated: false, completion: nil)
        }
    }
    
    public func setVpOffer(vpOffer: VerifyOfferPayload) {
        self.vpOffer = vpOffer
    }
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        cancelBtn.layer.borderWidth = 1
        cancelBtn.layer.borderColor = UIColor(hexCode: "FF8400").cgColor
        
        Task { @MainActor in
            do {
                try await VerifyVcProtocol.shared.preProcess(id:SDKUtils.generateMessageID(), txId: self.offerTxId, offerId: vpOffer?.offerId )
                
                verifierLbl.text = "The following certificate is submitted to the "+(VerifyVcProtocol.shared.verifyProfile?.profile.profile.verifier.name)!
                                
                let schemaData = try await CommnunicationClient().doGet(url: URL(string: (VerifyVcProtocol.shared.verifyProfile?.profile.profile.filter.credentialSchemas[0].id)!)!)
                let schema = try VCSchema.init(from: schemaData)
                    
                subjectLbl.text = schema.title
                issuanceDateLbl.text = VerifyVcProtocol.shared.verifyProfile?.profile.proof?.created
                
                let attributedString = NSMutableAttributedString()
                
                let schemas = VerifyVcProtocol.shared.verifyProfile?.profile.profile.filter.credentialSchemas
                attributedString.append(NSAttributedString(string: "Personal infomation submitted\n\n"))
                for schema in schemas! {
                    print("schema: \(try schema.toJson())")
                    for claim in schema.requiredClaims! {
                        attributedString.append(NSAttributedString(string: claim))
                        attributedString.append(NSAttributedString(string: "\n"))
                    }
                    self.contentsTxtView.attributedText = attributedString
                }
            } catch let error as WalletSDKError {
                print("error code: \(error.code), message: \(error.message)")
                PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
            } catch let error as WalletCoreError {
                print("error code: \(error.code), message: \(error.message)")
                PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
            } catch let error as CommunicationSDKError {
                print("error code: \(error.code), message: \(error.message)")
                PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
            }
        }
    }
}
    


