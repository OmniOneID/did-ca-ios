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
import UIKit
import DIDWalletSDK

public enum StepTypeEnum: String {
    case STEP_TYPE_1 = "Step1"
    case STEP_TYPE_2 = "Step2"
    case STEP_TYPE_3 = "Step3"
}

class StepViewController: UIViewController {
    
    @IBOutlet weak var numImg1: UIButton!
    @IBOutlet weak var numImg2: UIButton!
    @IBOutlet weak var numImg3: UIButton!
    
    @IBOutlet weak var step1Lbl: UILabel!
    @IBOutlet weak var step2Lbl: UILabel!
    @IBOutlet weak var step3Lbl: UILabel!
    
    @IBOutlet weak var lineImg1: UIButton!
    @IBOutlet weak var lineImg2: UIButton!
    
    private var stepType: StepTypeEnum = StepTypeEnum.STEP_TYPE_1
    
    public func setStepType(stepType: StepTypeEnum) {
        self.stepType = stepType
        print("[StepView] next step: \(self.stepType)")
        switch stepType {
        case .STEP_TYPE_1:
            print("1. Register a demo user.\n2. Set the wallet lock type.")
            break
        case .STEP_TYPE_2:
            print("1. Register a PIN to create a signature key.\n2. Register a user DID Document.")
            break
        case .STEP_TYPE_3:
            print("1. Authentication for signing user DID documents.")
            break
        }
    }
    
    private func showUI() {
        
//        self.stopLoading()
        
        let numOneTitle = "01"
        let numOneTitleAttributedString = NSMutableAttributedString(string: numOneTitle)
        let numTwoTitle = "02"
        let numTwoTitleAttributedString = NSMutableAttributedString(string: numTwoTitle)
        let numThreeTitle = "03"
        let numThreeTitleAttributedString = NSMutableAttributedString(string: numThreeTitle)
        
        switch self.stepType {
        case .STEP_TYPE_1:
            step1Lbl.textColor = UIColor(hexCode: "FF8400")
            step2Lbl.textColor = UIColor.black
            step3Lbl.textColor = UIColor.black
            
            numOneTitleAttributedString.addAttribute(.foregroundColor, value: UIColor.white, range: NSRange(location: 0, length: numOneTitle.count))
            numImg1.setAttributedTitle(numOneTitleAttributedString, for: .normal)
            numImg1.setBackgroundImage(UIImage(named: "property-active"), for: UIControl.State.normal)
            numImg2.setBackgroundImage(UIImage(named: "property-default"), for: UIControl.State.normal)
            numImg3.setBackgroundImage(UIImage(named: "property-default"), for: UIControl.State.normal)
            lineImg1.setImage(UIImage(named: "line_gray"), for: UIControl.State.normal)
            lineImg2.setImage(UIImage(named: "line_gray"), for: UIControl.State.normal)
            break
        case .STEP_TYPE_2:
            step1Lbl.textColor = UIColor.black
            step2Lbl.textColor = UIColor(hexCode: "FF8400")
            step3Lbl.textColor = UIColor.black
            
            numOneTitleAttributedString.addAttribute(.foregroundColor, value: UIColor(hexCode: "FF8400"), range: NSRange(location: 0, length: numOneTitle.count))
            numImg1.setAttributedTitle(numOneTitleAttributedString, for: .normal)
            numImg1.setBackgroundImage(UIImage(named: "property-after"), for: UIControl.State.normal)
            
            numTwoTitleAttributedString.addAttribute(.foregroundColor, value: UIColor.white, range: NSRange(location: 0, length: numTwoTitle.count))
            numImg2.setAttributedTitle(numTwoTitleAttributedString, for: .normal)
            numImg2.setBackgroundImage(UIImage(named: "property-active"), for: UIControl.State.normal)
            
            numImg3.setBackgroundImage(UIImage(named: "property-default"), for: UIControl.State.normal)
            lineImg1.setImage(UIImage(named: "line_blue"), for: UIControl.State.normal)
            lineImg2.setImage(UIImage(named: "line_gray"), for: UIControl.State.normal)
            break
        case .STEP_TYPE_3:
            step1Lbl.textColor = UIColor.black
            step2Lbl.textColor = UIColor.black
            step3Lbl.textColor = UIColor(hexCode: "FF8400")
            
            numOneTitleAttributedString.addAttribute(.foregroundColor, value: UIColor(hexCode: "FF8400"), range: NSRange(location: 0, length: numOneTitle.count))
            numImg1.setAttributedTitle(numOneTitleAttributedString, for: .normal)
            numImg1.setBackgroundImage(UIImage(named: "property-after"), for: UIControl.State.normal)
            
            numTwoTitleAttributedString.addAttribute(.foregroundColor, value: UIColor(hexCode: "FF8400"), range: NSRange(location: 0, length: numTwoTitle.count))
            numImg2.setAttributedTitle(numTwoTitleAttributedString, for: .normal)
            numImg2.setBackgroundImage(UIImage(named: "property-after"), for: UIControl.State.normal)
            
            numThreeTitleAttributedString.addAttribute(.foregroundColor, value: UIColor.white, range: NSRange(location: 0, length: numThreeTitle.count))
            numImg3.setAttributedTitle(numThreeTitleAttributedString, for: .normal)
            numImg3.setBackgroundImage(UIImage(named: "property-active"), for: UIControl.State.normal)
            lineImg1.setImage(UIImage(named: "line_blue"), for: UIControl.State.normal)
            lineImg2.setImage(UIImage(named: "line_blue"), for: UIControl.State.normal)
            break
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        showUI()
    }
    
    private func nextForStep2()
    {
        
        ActivityUtil.show(vc: self){
            try await RegUserProtocol.shared.preProcess()
        } completeClosure: {
            self.registerPin()
        } failureCloseClosure: { title, message in
            PopupUtils.showAlertPopup(title: title,
                                      content: message,
                                      VC: self)
        }
    }
    
    private func nextForStep3() {
        // PIN view
        let pinVC = UIStoryboard.init(name: "PIN", bundle: nil).instantiateViewController(withIdentifier: "PincodeViewController") as! PincodeViewController
        pinVC.modalPresentationStyle = .fullScreen
        pinVC.setRequestType(type: PinCodeTypeEnum.PIN_CODE_AUTHENTICATION_SIGNATURE_TYPE)
        pinVC.confirmButtonCompleteClosure = { passcode in
            
            ActivityUtil.show(vc: self){
                let signedDIDDoc = try WalletAPI.shared.createSignedDIDDoc(passcode: passcode)
                // 사용자 등록 요청
                try await RegUserProtocol.shared.process(signedDidDoc: signedDIDDoc)
                
                let didDoc = try WalletAPI.shared.getDidDocument(type: DidDocumentType.HolderDidDocumnet)
                print("holderDidDoc : \(try didDoc.toJson(isPretty: true))")
                
                // out of scope
                let requestJsonData = try UpdatePushToken(id: SDKUtils.generateMessageID(), did: didDoc.id, appId: Properties.getCaAppId()!, pushToken: Properties.getPushToken() ?? "").toJsonData()
                _ = try await CommnunicationClient.doPost(url: URL(string: URLs.TAS_URL + "/tas/api/v1/update-push-token")!, requestJsonData: requestJsonData)
                
                Properties.setRegDidDocCompleted(status: true)
                
            } completeClosure: {
                self.goMainView()
            } failureCloseClosure: { title, message in
                PopupUtils.showAlertPopup(title: title,
                                          content: message,
                                          VC: self)
            }
        }
        pinVC.cancelButtonCompleteClosure = {
            PopupUtils.showAlertPopup(title: "Notification", content: "canceled by user", VC: self)
        }
        DispatchQueue.main.async {
            self.present(pinVC, animated: false, completion: nil)
        }
    }
    
    func registerPin()
    {
        let pinVC = UIStoryboard.init(name: "PIN", bundle: nil).instantiateViewController(withIdentifier: "PincodeViewController") as! PincodeViewController
        pinVC.modalPresentationStyle = .fullScreen
        pinVC.setRequestType(type: PinCodeTypeEnum.PIN_CODE_REGISTRATION_SIGNATURE_TYPE)
        pinVC.confirmButtonCompleteClosure = { passcode in
            
            ActivityUtil.show(vc: self){
                try WalletAPI.shared.generateKeyPair(hWalletToken: RegUserProtocol.shared.getWalletToken(), keyId: "keyagree", algType: AlgorithmType.secp256r1)
                // register PIN
                try WalletAPI.shared.generateKeyPair(hWalletToken: RegUserProtocol.shared.getWalletToken(), passcode: passcode, keyId: "pin", algType: AlgorithmType.secp256r1)
            } completeClosure: {
                self.doNext()
            } failureCloseClosure: { title, message in
                PopupUtils.showAlertPopup(title: title,
                                          content: message,
                                          VC: self)
            }
        }
        pinVC.cancelButtonCompleteClosure = {
            PopupUtils.showAlertPopup(title: "Notification", content: "canceled by user", VC: self)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.present(pinVC, animated: false, completion: nil)
        }
    }
    
    @IBAction func nextBtnAction() {
        
        
        switch self.stepType {
        /**
            1. Register a demo user
            2. Set the wallet lock type
         */
        case .STEP_TYPE_1:
            showUserRegWebView()
            break
        /**
            1. Register a pin to create a signature key
            2. Register a user DID Document
         */
        case .STEP_TYPE_2:
            nextForStep2()
            break
        case .STEP_TYPE_3:
            nextForStep3()
            break
        }
    }
    
    private func doNext() {
         
        let popupVC = UIStoryboard.init(name: "Popup", bundle: nil).instantiateViewController(withIdentifier: "TwoButtonDialogViewController") as! TwoButtonDialogViewController
        popupVC.modalPresentationStyle = .overCurrentContext
        popupVC.setContentsMessage(message: "Would you like to additionally register biometric authentication?")
        popupVC.confirmButtonCompleteClosure = { [self] in
            ActivityUtil.show(vc: self){
                // register BIO
                _ = try WalletAPI.shared.generateKeyPair(hWalletToken: RegUserProtocol.shared.getWalletToken(), keyId: "bio", algType: AlgorithmType.secp256r1, promptMsg: "please touch your fingerprint")
                try WalletAPI.shared.createHolderDIDDocument(hWalletToken: RegUserProtocol.shared.getWalletToken())
            } completeClosure: {
                self.presentSubmitViewController()
            } failureCloseClosure: { title, message in
                PopupUtils.showAlertPopup(title: title,
                                          content: message,
                                          VC: self)
            }
        }
        popupVC.cancelButtonCompleteClosure = { [self] in
            ActivityUtil.show(vc: self){
                try WalletAPI.shared.createHolderDIDDocument(hWalletToken: RegUserProtocol.shared.getWalletToken())
            } completeClosure: {
                self.presentSubmitViewController()
            } failureCloseClosure: { title, message in
                PopupUtils.showAlertPopup(title: title,
                                          content: message,
                                          VC: self)
            }
            
        }
        DispatchQueue.main.async {
//            self.stopLoading()
            self.present(popupVC, animated: false, completion: nil) }
    }
    
    private func presentSubmitViewController() {
        self.setStepType(stepType: StepTypeEnum.STEP_TYPE_3)
        showUI()
    }
}

//Move to other viewController
extension StepViewController
{
    func showUserRegWebView()
    {
        let stepVC = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "UserRegWebViewController") as! UserRegWebViewController
        stepVC.modalPresentationStyle = .fullScreen
        DispatchQueue.main.async {

            self.present(stepVC, animated: false, completion: nil)
        }
    }
    
    func goMainView()
    {
        let submitVC = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "MainViewController") as! MainViewController
        submitVC.modalPresentationStyle = .fullScreen
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.present(submitVC, animated: false)
        }
    }
}
