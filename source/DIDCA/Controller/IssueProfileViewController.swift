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

protocol DismissDelegate: AnyObject {
    func didDidmissWithData()
}

class IssueProfileViewController: UIViewController, DismissDelegate {
    
    func didDidmissWithData() {
        issueVcProcess()
    }
    
    
    // MARK
    @IBOutlet weak var issuanceBtn: UIButton!
    @IBOutlet weak var cancelBtn: UIButton!
    @IBOutlet weak var issuanceDateLbl: UILabel!
    @IBOutlet weak var certImage: UIImageView!
    @IBOutlet weak var issuerInfoLbl: UILabel!
    @IBOutlet weak var vcNmLbl: UILabel!
    
    @IBOutlet weak var IssueInfoDescLbl: UILabel!
    
    private var isWebView: Bool? = nil
    
    private var vcOfferPayload: IssueOfferPayload? = nil
    
    public var vcSchemaId : String!
    
    @IBAction func cancelBtnAction(_ sender: Any) {
        DispatchQueue.main.async {
            self.dismiss(animated: false, completion: nil)
        }
    }
    
    public func setVcOffer(vcOfferPayload: IssueOfferPayload, isWebView: Bool? = false) {
        self.vcOfferPayload = vcOfferPayload
        self.isWebView = isWebView
        print("setVcOffer isWebView: \(String(describing: self.isWebView))")
    }
    
    @IBAction func issuanceBtnAction(_ sender: Any) {
        if self.isWebView == true {
            let issueVcWeb = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "IssueVCWebViewController") as! IssueVCWebViewController
            issueVcWeb.delegate = self
            issueVcWeb.vcSchemaId = self.vcSchemaId
            issueVcWeb.modalPresentationStyle = .fullScreen
            DispatchQueue.main.async {
                self.present(issueVcWeb, animated: false, completion: nil)
            }
        }
        else {
            issueVcProcess()
        }
    }
    private func issueVcProcess() {
        
        do {
            let keyInfos: [KeyInfo] = try WalletAPI.shared.getKeyInfos(ids: ["pin", "bio"])
            print("keyInfos: \(keyInfos)")
            
            ActivityUtil.show(vc: self){
                _ = try await IssueVcProtocol.shared.process()
                print("issueProfile: \(try IssueVcProtocol.shared.getIssueProfile()!.toJson())")
                Properties.setSubmitCompleted(status: true)
            } completeClosure: {
                self.showIssueCompletedView()
            } failureCloseClosure: { title, message in
                PopupUtils.showAlertPopup(title: title,
                                          content: message,
                                          VC: self)
            }
        } catch {
            
            print("issueVcProcess error: \(error.localizedDescription)")
            self.showPin()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        ActivityUtil.show(vc: self){
            try await IssueVcProtocol.shared.preProcess(vcPlanId: self.vcOfferPayload!.vcPlanId,
                                                        issuer: self.vcOfferPayload!.issuer,
                                                        offerId: self.vcOfferPayload!.offerId)
        } completeClosure: {
            let profile = IssueVcProtocol.shared.getIssueProfile()!.profile
            
            DispatchQueue.main.async
            {
                self.vcNmLbl.text = profile.title
                
                self.issuerInfoLbl.text = "The certificate will be issued by "+(profile.profile.issuer.name)
                self.issuanceDateLbl.text = "Issuance Application Date:\n "+SDKUtils.convertDateFormat2(dateString: (profile.proof?.created)!)!
                self.IssueInfoDescLbl.text = "The identity certificate issued by "+(profile.profile.issuer.name) + " is stored in this certificate."    
            }
            
        } failureCloseClosure: { title, message in
            PopupUtils.showAlertPopup(title: title,
                                      content: message,
                                      VC: self)
        }
    }
}

extension IssueProfileViewController
{
    func showIssueCompletedView()
    {
        let issueCompletedVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "IssueCompletedViewController") as! IssueCompletedViewController
        issueCompletedVC.modalPresentationStyle = .fullScreen
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.present(issueCompletedVC, animated: false, completion: nil)
        }
    }
    
    func showPin()
    {
        let pinVC = UIStoryboard.init(name: "PIN", bundle: nil).instantiateViewController(withIdentifier: "PincodeViewController") as! PincodeViewController
        pinVC.modalPresentationStyle = .fullScreen
        pinVC.setRequestType(type: PinCodeTypeEnum.PIN_CODE_AUTHENTICATION_SIGNATURE_TYPE)
        pinVC.confirmButtonCompleteClosure = { passcode in
            
            ActivityUtil.show(vc: self){
                _ = try await IssueVcProtocol.shared.process(passcode: passcode)

                Properties.setSubmitCompleted(status: true)
            } completeClosure: {
                self.showIssueCompletedView()
            } failureCloseClosure: { title, message in
                PopupUtils.showAlertPopup(title: title,
                                          content: message,
                                          VC: self)
            }
        }
        pinVC.cancelButtonCompleteClosure = {
            PopupUtils.showAlertPopup(title: "Notification", content: "canceled by user", VC: self)
        }
        DispatchQueue.main.async { self.present(pinVC, animated: false, completion: nil) }
    }
}
