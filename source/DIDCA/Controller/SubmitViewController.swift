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
import DIDCommunicationSDK
import DIDDataModelSDK
import DIDCoreSDK

class SubmitViewController: UIViewController {
    
    @IBOutlet weak var titleLbl: UILabel!
    @IBOutlet weak var nameLbl: UILabel!
    @IBOutlet weak var birthLbl: UILabel!
    
    @IBOutlet weak var indicator: UIActivityIndicatorView!
    
    @IBOutlet weak var issueVcBtn: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        Properties.setSubmitCompleted(status: true)
        indicator.stopAnimating()
        
        if Properties.getSubmitCompleted()! {
//            self.issueVcBtn.setBackgroundImage(UIImage(named: "User"), for: .normal)
            
//            self.titleLbl.text = WalletAPI.shared.verifiableCredential?.evidence[0].evidenceDocument
//            self.nameLbl.text = WalletAPI.shared.verifiableCredential?.credentialSubject.claims[0].value.appending((WalletAPI.shared.verifiableCredential?.credentialSubject.claims[1].value)!)
            
//            self.birthLbl.text = WalletAPI.shared.verifiableCredential?.credentialSubject.claims[2].value
//            self.generateImg(base64String:(WalletAPI.shared.verifiableCredential?.credentialSubject.claims[4].value)!)
            
        } else {
            self.issueVcBtn.setBackgroundImage(UIImage(named: "Pin_bt_bg_01"), for: .normal)
        }
    }
    
    @IBAction func issueVcBtnAction(_ sender: Any) {
//        requestVC()
        // 발급가능 목록 띄우기
    }
    
    private func requestVP(qrString: String) async throws {
        if let data = qrString.data(using: .utf8) {
            let vpOffer = try VpOfferWrapper(from: data)
            print("vpOffer JSON: \(try vpOffer.toJson())")
            
            let verifyProfileVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "VerifyProfileViewController") as! VerifyProfileViewController
            verifyProfileVC.modalPresentationStyle = .fullScreen
            DispatchQueue.main.async {
                self.present(verifyProfileVC, animated: false, completion: nil)
            }
        }
    }
    
    private func requestVC(qrString: String) throws {
        if let data = qrString.data(using: .utf8) {
            let vcOffer = try IssueOfferPayload(from: data)
            print("vcOffer JSON: \(try vcOffer.toJson())")
            
            let issueProfileVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "IssueProfileViewController") as! IssueProfileViewController
            issueProfileVC.modalPresentationStyle = .fullScreen
            DispatchQueue.main.async {
                self.present(issueProfileVC, animated: false, completion: nil)
            }
        }
    }
    
    private func submitVP() {
        // Go to the submission completion screen
        let verifyProfileVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "VerifyProfileViewController") as! VerifyProfileViewController
        verifyProfileVC.modalPresentationStyle = .fullScreen
        DispatchQueue.main.async {
            self.present(verifyProfileVC, animated: false, completion: nil)
        }
    }
    
    @IBAction func submitButtonAction(_ sender: Any) {
        let qrVC = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "QRScanViewController") as! QRScanViewController
        qrVC.delegate = self
        qrVC.modalPresentationStyle = .popover
        DispatchQueue.main.async {
            self.present(qrVC, animated: false, completion: nil)
        }        
    }
    
    @IBAction func scanQR(_ sender: Any) {
        let qrVC = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "QRScanViewController") as! QRScanViewController
        qrVC.delegate = self
        qrVC.modalPresentationStyle = .popover

        DispatchQueue.main.async {
            self.present(qrVC, animated: false, completion: nil)
        }
    }
}

/**
 def object VcOfferPayload: "VC offer payload"
 {
    + uuid "offerId" : "offer id"
    + OFFER_TYPE "type" : "offer type", value("IssueOffer")
    + vcPlanId "vcPlanId" : "VC plan id"
    + did "issuer" : "issuer DID"
    - utcDatetime "validUntil": "발급가능 종료일시"
 }
 */

extension SubmitViewController: ScanQRViewControllerDelegate {
    
    
    func extractStringfromQRCode(qrString: String) {
        
        print("qrString \(qrString)")
        
        Task {
            do {
                try await requestVC(qrString: qrString)
//                try await requestVP(qrString: qrString)
            } catch let error as WalletSDKError {
                print("error code: \(error.code), message: \(error.message)")
                PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
            } catch let error as WalletCoreError {
                print("error code: \(error.code), message: \(error.message)")
                PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
            } catch let error as CommunicationSDKError {
                print("error code: \(error.code), message: \(error.message)")
                PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
            } catch {
                print("error: \(error)")
            }
        }
    }
}
