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

protocol DismissDelegate: AnyObject {
    func didDidmissWithData()
}

class IssueProfileViewController: UIViewController, DismissDelegate {
    
    func didDidmissWithData() {
        self.stopLoading()
        issueVcProcess()
    }
    
    @IBOutlet weak var indicator: UIActivityIndicatorView!
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
    
    private func startLoading() {
        self.indicator.isHidden = false
        self.indicator.startAnimating()
    }
    private func stopLoading() {
        self.indicator.isHidden = true
        self.indicator.stopAnimating()
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
        startLoading()
        Task {
            do {
                let keyInfos: [KeyInfo] = try WalletAPI.shared.getKeyInfos(ids: ["pin", "bio"])
                print("keyInfos: \(keyInfos)")
                print("issueProfile: \(try IssueVcProtocol.shared.getIssueProfile()!.toJson())")
                                
                _ = try await IssueVcProtocol.shared.process()
                    
                Properties.setSubmitCompleted(status: true)
                
                let issueCompletedVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "IssueCompletedViewController") as! IssueCompletedViewController
                issueCompletedVC.modalPresentationStyle = .fullScreen
                self.stopLoading()
                DispatchQueue.main.async {
                    self.present(issueCompletedVC, animated: false, completion: nil)
                }
            } catch {
                
                print("issueVcProcess error: \(error.localizedDescription)")
                self.stopLoading()
                let pinVC = UIStoryboard.init(name: "PIN", bundle: nil).instantiateViewController(withIdentifier: "PincodeViewController") as! PincodeViewController
                pinVC.modalPresentationStyle = .fullScreen
                pinVC.setRequestType(type: PinCodeTypeEnum.PIN_CODE_AUTHENTICATION_SIGNATURE_TYPE)
                pinVC.confirmButtonCompleteClosure = { passcode in
                    
                    Task { @MainActor in
                        do {
                            _ = try await IssueVcProtocol.shared.process(passcode: passcode)

                            Properties.setSubmitCompleted(status: true)
                            
                            let issueCompletedVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "IssueCompletedViewController") as! IssueCompletedViewController
                            issueCompletedVC.modalPresentationStyle = .fullScreen
                            self.stopLoading()
                            DispatchQueue.main.async {self.present(issueCompletedVC, animated: false, completion: nil)}
                        } catch let error as WalletSDKError {
                             self.stopLoading()
                            print("error code: \(error.code), message: \(error.message)")
                            PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
                        } catch let error as WalletCoreError {
                            self.stopLoading()
                            print("error code: \(error.code), message: \(error.message)")
                            PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
                        } catch let error as CommunicationSDKError {
                            self.stopLoading()
                            print("error code: \(error.code), message: \(error.message)")
                            PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
                        } catch {
                            self.stopLoading()
                            print("error :\(error)")
                        }
                    }
                }
                pinVC.cancelButtonCompleteClosure = { 
                    PopupUtils.showAlertPopup(title: "Notification", content: "canceled by user", VC: self)
                }
                DispatchQueue.main.async { self.present(pinVC, animated: false, completion: nil) }
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        startLoading()
        cancelBtn.layer.borderWidth = 1
        cancelBtn.layer.borderColor = UIColor(hexCode: "FF8400").cgColor
        
        Task { @MainActor in
            do {
                try await IssueVcProtocol.shared.preProcess(vcPlanId: vcOfferPayload!.vcPlanId, issuer: vcOfferPayload!.issuer, offerId: vcOfferPayload!.offerId)
                

                vcNmLbl.text = IssueVcProtocol.shared.getIssueProfile()?.profile.title
                
                issuerInfoLbl.text = "The certificate will be issued by "+(IssueVcProtocol.shared.getIssueProfile()?.profile.profile.issuer.name)!
                issuanceDateLbl.text = "Issuance Application Date:\n "+SDKUtils.convertDateFormat2(dateString: (IssueVcProtocol.shared.getIssueProfile()?.profile.proof?.created)!)!                
                IssueInfoDescLbl.text = "The identity certificate issued by "+(IssueVcProtocol.shared.getIssueProfile()?.profile.profile.issuer.name)!+" is stored in this certificate."
                stopLoading()
                
            } catch let error as WalletSDKError {
                stopLoading()
                print("error code: \(error.code), message: \(error.message)")
                PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
            } catch let error as WalletCoreError {
                stopLoading()
                print("error code: \(error.code), message: \(error.message)")
                PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
            } catch let error as CommunicationSDKError {
                stopLoading()
                print("error code: \(error.code), message: \(error.message)")
                PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
            } catch {
                stopLoading()
                print("error :\(error)")
            }
        }
    }
}
