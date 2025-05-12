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


class VCDetailViewController: UIViewController {
    
    weak var delegate: DismissDelegate?
    @IBOutlet weak var txtView: UITextView!
    @IBOutlet weak var nameLbl: UILabel!
    
    private var vc: VerifiableCredential? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        do {
            nameLbl.text = Properties.getUserName()
            
            if self.vc != nil {
                let attributedString = NSMutableAttributedString()
                for claim in vc!.credentialSubject.claims {
                    print("claim: \(claim)")
                    
                    if claim.type.rawValue == "image" {
                        // 이미지를 생성합니다.
                        let image = try! SDKUtils.generateImg(base64String: claim.value)
                        let targetSize = CGSize(width: 100, height: 100)
                        UIGraphicsBeginImageContextWithOptions(targetSize, false, 0.0)
                        image.draw(in: CGRect(origin: .zero, size: targetSize))
                        let newImage = UIGraphicsGetImageFromCurrentImageContext()
                        UIGraphicsEndImageContext()
                        
                        
                        // Add an image by creating an NSAttributedString.
                        let attachment = NSTextAttachment()
                        attachment.image = newImage
                        
                        let imageString = NSAttributedString(attachment: attachment)
                        
                        // Add an image to UITextView.
                        attributedString.append(NSAttributedString(string: "["+claim.caption+"]"))
                        attributedString.append(NSAttributedString(string: "\n"))
                        attributedString.append(imageString)
                        attributedString.append(NSAttributedString(string: "\n\n"))
                        
                        
                    } else {
                        attributedString.append(NSAttributedString(string: "["+claim.caption+"]"))
                        attributedString.append(NSAttributedString(string: "\n"))
                        attributedString.append(NSAttributedString(string: claim.value))
                        attributedString.append(NSAttributedString(string: "\n\n"))
//                     = self.txtView.text.appending(claim.code).appending("\n").appending(claim.value).appending("\n\n")
                    }
                    self.txtView.attributedText = attributedString
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
    
    public func setVcInfo(vc: VerifiableCredential!) {
        self.vc = vc
    }
    
    @IBAction func okBtnAction(_ sender: Any) {
        self.dismiss(animated: false, completion: nil)
    }
    
    @IBAction func deleteVcBtnAction(_ sender: Any) {

        Task { @MainActor in
            do {
                try await RevokeVcProtocol.shared.preProcess(vcId: vc!.id)
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
                
            do {
                _ = try WalletAPI.shared.getKeyInfos(ids: ["pin","bio"])
                
                let selectAuthVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "SelectAuthViewController") as! SelectAuthViewController
                selectAuthVC.setCommandType(command: 0)
                selectAuthVC.modalPresentationStyle = .fullScreen
                DispatchQueue.main.async { self.present(selectAuthVC, animated: false, completion: nil) }
            } catch {
                let pinVC = UIStoryboard.init(name: "PIN", bundle: nil).instantiateViewController(withIdentifier: "PincodeViewController") as! PincodeViewController
                pinVC.modalPresentationStyle = .fullScreen
                pinVC.setRequestType(type: PinCodeTypeEnum.PIN_CODE_AUTHENTICATION_SIGNATURE_TYPE)
                pinVC.confirmButtonCompleteClosure = { [self] passcode in
                    Task { @MainActor in
                        do {
                            _ = try await RevokeVcProtocol.shared.process(passcode: passcode)
                            
                            let mainVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "MainViewController") as! MainViewController
                            mainVC.modalPresentationStyle = .fullScreen
                            DispatchQueue.main.async {
                                self.present(mainVC, animated: false, completion: nil)
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
                }
                pinVC.cancelButtonCompleteClosure = { 
                    PopupUtils.showAlertPopup(title: "Notification", content: "canceled by user", VC: self)
                }
                DispatchQueue.main.async { self.present(pinVC, animated: false, completion: nil) }
            }
        
        }
    }
}
