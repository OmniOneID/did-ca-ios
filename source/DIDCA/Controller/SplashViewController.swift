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


class SplashViewController: UIViewController {
    
    private var vcOfferPayload: IssueOfferPayload? = nil
    
    public func setVcOffer(vcOfferPayload: IssueOfferPayload) {
        self.vcOfferPayload = vcOfferPayload
    }
    
    private func checkWalletLock() {
        // switch screens when wallet type is Lock
        do {
            if try WalletAPI.shared.isLock() {
                // PIN 화면 호출
                let pinVC = UIStoryboard.init(name: "PIN", bundle: nil).instantiateViewController(withIdentifier: "PincodeViewController") as! PincodeViewController
                pinVC.modalPresentationStyle = .fullScreen
                pinVC.setRequestType(type: PinCodeTypeEnum.PIN_CODE_AUTHENTICATION_LOCK_TYPE)
                pinVC.confirmButtonCompleteClosure = { [self] passcode in
                    
                    if let vcOfferPayload {
                        let issueProfileVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "IssueProfileViewController") as! IssueProfileViewController
                        issueProfileVC.setVcOffer(vcOfferPayload: vcOfferPayload)
                        issueProfileVC.modalPresentationStyle = .fullScreen
                                
                        (UIApplication.shared.connectedScenes.first?.delegate as? SceneDelegate)?.changeRootVC(issueProfileVC, animated: false)
                    } else {
                        
                        // 유저등록 유무
                        if Properties.getSubmitCompleted() == true {
                            let mainVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "MainViewController") as! MainViewController
                            mainVC.modalPresentationStyle = .fullScreen
                            DispatchQueue.main.async {
                                self.present(mainVC, animated: false, completion: nil)
                            }
                        } else {
                            self.navigateToNextViewController()
                        }
                    }
                }
                pinVC.cancelButtonCompleteClosure = {
                    exit(1)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    //                DispatchQueue.main.async {
                    self.present(pinVC, animated: false, completion: nil)
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.navigateToNextViewController()
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
        } catch {
            print("error :\(error)")
        }
    }
    
    
    private func createWallet() async {
                
        // create wallet
        do {
            if try WalletAPI.shared.isExistWallet() == false {
                print("createWallet: \(try await WalletAPI.shared.createWallet(tasURL: URLs.TAS_URL, walletURL: URLs.WALLET_URL))")
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
        } catch {
            print("error \(error)")
        }
        
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        Properties.generateCaAppId()
        Task { @MainActor in
            await createWallet()
        
            checkWalletLock()
        }
    }
    
    private func navigateToNextViewController() {
    
        if let vcOfferPayload {
            let issueProfileVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "IssueProfileViewController") as! IssueProfileViewController
            issueProfileVC.setVcOffer(vcOfferPayload: vcOfferPayload)
            issueProfileVC.modalPresentationStyle = .fullScreen
                    
            (UIApplication.shared.connectedScenes.first?.delegate as? SceneDelegate)?.changeRootVC(issueProfileVC, animated: false)
            return
        }
        
        if Properties.getUserId() == nil {
            let stepVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "StepViewController") as! StepViewController
            stepVC.setStepType(stepType: StepTypeEnum.STEP_TYPE_1)
            stepVC.modalPresentationStyle = .fullScreen
            DispatchQueue.main.async { self.present(stepVC, animated: false, completion: nil) }
        } else {
            if Properties.getRegDidDocCompleted() == true {
                let nextVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "MainViewController") as! MainViewController
                nextVC.modalPresentationStyle = .fullScreen
                DispatchQueue.main.async { self.present(nextVC, animated: false, completion: nil) }
            } else {
                
                Task { @MainActor in
                    let isAnyKey = try! WalletAPI.shared.isAnyKeysSaved()
                    
                    let stepVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "StepViewController") as! StepViewController
                    if isAnyKey {
                        
                        try await RegUserProtocol.shared.preProcess()
                        stepVC.setStepType(stepType: StepTypeEnum.STEP_TYPE_3)
                        
                    } else {
                        stepVC.setStepType(stepType: StepTypeEnum.STEP_TYPE_2)
                    }
                    stepVC.modalPresentationStyle = .fullScreen
                    DispatchQueue.main.async { self.present(stepVC, animated: false, completion: nil) }
                }
            }
        }
    }
}
