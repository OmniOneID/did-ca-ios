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
import DIDCoreSDK
import DIDWalletSDK
import DIDCommunicationSDK
import DIDDataModelSDK

class SelectAuthViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    private var list = [KeyInfo]()
    private var command: Int = 0
    
    
    public func setCommandType(command: Int) {
        self.command = command
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        do {
            // It needs to be divided into submission and VC disposal.
            if self.command == 1 {
                let type: VerifyAuthType = .init(rawValue: VerifyVcProtocol.shared.getVerifyProfile()!.profile.profile.process.authType?.rawValue ?? 0)
                //            let type: VerifyAuthType = .init(rawValue: 0)
                list = try WalletAPI.shared.getKeyInfos(keyType: type)
            } else {
                list = try WalletAPI.shared.getKeyInfos(keyType: RevokeVcProtocol.shared.getAuthType())
            }
            
            var keyagreeIndex = 0
            for keyInfo in list {
                print("keyInfo: \(keyInfo)")
                if keyInfo.id == "keyagree" {
                    list.remove(at: keyagreeIndex)
                }
                keyagreeIndex = +1
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
    
    @IBAction func cancelBtnAction(_ sender: Any) {
        DispatchQueue.main.async {
            self.dismiss(animated: false, completion: nil)
        }
    }
    
    func showUI(type: String) {
        if type == "pin" {
            let pinVC = UIStoryboard.init(name: "PIN", bundle: nil).instantiateViewController(withIdentifier: "PincodeViewController") as! PincodeViewController
            pinVC.modalPresentationStyle = .fullScreen
            pinVC.setRequestType(type: PinCodeTypeEnum.PIN_CODE_AUTHENTICATION_SIGNATURE_TYPE)
            pinVC.confirmButtonCompleteClosure = { [self] passcode in
                Task { @MainActor in
                    do {
                        if self.command == 1 {
                            let schemas = VerifyVcProtocol.shared.verifyProfile!.profile.profile.filter.credentialSchemas
                            let vcs = try WalletAPI.shared.getAllCrentials(hWalletToken: VerifyVcProtocol.shared.getWalletToken())!
                            var claimInfos:[ClaimInfo]? = []
                            for schema in schemas {
                                for vc in vcs {
                                    if vc.credentialSchema.id == schema.id {
                                        let claimInfo = ClaimInfo(credentialId: vc.id, claimCodes: schema.requiredClaims!)
                                        claimInfos?.append(claimInfo)
                                    }
                                }
                            }
                                
                            try await VerifyVcProtocol().process(hWalletToken: VerifyVcProtocol.shared.getWalletToken(),txId: VerifyVcProtocol.shared.getTxId(), claimInfos: claimInfos, verifierProfile: VerifyVcProtocol.shared.getVerifyProfile()!, passcode: passcode)
                            
                            let verifyCompletedVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "VerifyCompletedViewController") as! VerifyCompletedViewController
                            verifyCompletedVC.modalPresentationStyle = .fullScreen
                            DispatchQueue.main.async {
                                self.present(verifyCompletedVC, animated: false, completion: nil)
                            }
                            
                        } else {
                            
                            _ = try await RevokeVcProtocol.shared.process(passcode: passcode)
                            let mainVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "MainViewController") as! MainViewController
                            mainVC.modalPresentationStyle = .fullScreen
                            DispatchQueue.main.async {
                                self.present(mainVC, animated: false, completion: nil)
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
            }
            pinVC.cancelButtonCompleteClosure = { 
                PopupUtils.showAlertPopup(title: "Notification", content: "canceled by user", VC: self)
            }
            DispatchQueue.main.async { self.present(pinVC, animated: false, completion: nil) }
            
        } else if type == "bio" {
            Task { @MainActor in
                do {
                    
                    if self.command == 1 {
                        let schemas = VerifyVcProtocol.shared.verifyProfile!.profile.profile.filter.credentialSchemas
                        let vcs = try WalletAPI.shared.getAllCrentials(hWalletToken: VerifyVcProtocol.shared.getWalletToken())!
                        var claimInfos:[ClaimInfo]? = []
                        for schema in schemas {
                            for vc in vcs {
                                if vc.credentialSchema.id == schema.id {
                                    let claimInfo = ClaimInfo(credentialId: vc.id, claimCodes: schema.requiredClaims!)
                                    claimInfos?.append(claimInfo)
                                }
                            }
                        }
                            
                        try await VerifyVcProtocol().process(hWalletToken: VerifyVcProtocol.shared.getWalletToken(), txId: VerifyVcProtocol.shared.getTxId(), claimInfos: claimInfos, verifierProfile: VerifyVcProtocol.shared.getVerifyProfile()!)
                        
                        
                        let verifyCompletedVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "VerifyCompletedViewController") as! VerifyCompletedViewController
                        verifyCompletedVC.modalPresentationStyle = .fullScreen
                        DispatchQueue.main.async {
                            self.present(verifyCompletedVC, animated: false, completion: nil)
                        }
                        
                    } else {
                        _ = try await RevokeVcProtocol.shared.process()
                        let mainVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "MainViewController") as! MainViewController
                        mainVC.modalPresentationStyle = .fullScreen
                        DispatchQueue.main.async {
                            self.present(mainVC, animated: false, completion: nil)
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
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return list.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "AuthTypeCell") else {
            return UITableViewCell()
        }
        
        switch list[indexPath.row].id {
        case "keyagree":
            cell.textLabel?.text = "ETC"
            break;
        case "bio":
            cell.textLabel?.text = "BIO"
            break;
        case "pin":
            cell.textLabel?.text = "PIN"
            break;
        default:
            fatalError()
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 100
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        showUI(type: list[indexPath.row].id)
    }
}

