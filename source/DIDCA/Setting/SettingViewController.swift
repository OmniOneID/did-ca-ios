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

import UIKit
import DIDWalletSDK

enum TitleOption : Int, Comparable
{
    static func < (lhs: TitleOption, rhs: TitleOption) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    case tasURL
    case verifierURL
    case did
    case userAuthentication
    case pinSettings
    case changePIN4Sign
    case changePIN4Unlock
    case biometricsSettings
    case settingBiometrics
    
    var title : String
    {
        switch self
        {
        case .tasURL:             "TAS URL"
        case .verifierURL:        "Verifier URL"
        case .did:                "DID"
        case .userAuthentication: "User Authentication Settings"
        case .pinSettings:        "PIN Settings"
        case .changePIN4Sign:     "Change PIN for Sign"
        case .changePIN4Unlock:   "Change PIN for Unlock"
        case .biometricsSettings: "Biometrics Settings"
        case .settingBiometrics:  "Setting up the biometrics for Signing"
        }
    }
    
    
    func getSubtitles() -> [TitleOption]
    {
        switch self
        {
        case .pinSettings:          [.changePIN4Sign, .changePIN4Unlock]
        case .biometricsSettings:   [.settingBiometrics]
        default: []
        }
    }
}


class SettingViewController: UITableViewController {
    
    public var contents: [TitleOption] = []
    {
        didSet{
            contents = contents.sorted()
        }
    }
    
    var expanded : [TitleOption] = []
    
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return contents.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
    {
        let row = indexPath.row
        let option = contents[row]
        
        if option < .pinSettings
        {
            let cell = tableView.dequeueReusableCell(withIdentifier: "SettingCell", for: indexPath) as! SettingCell
            cell.content1.text = option.title
            
            switch option
            {
            case .tasURL:
                cell.content2.text = URLs.TAS_URL
            case .verifierURL:
                cell.content2.text = URLs.VERIFIER_URL
            case .did:
                cell.content2.text = try! WalletAPI.shared.getDidDocument(type: .HolderDidDocumnet).id
            case .userAuthentication:
                cell.content2.text = "Provides management of authentication methods."
            default:
                ()
            }
            return cell
        }
        else
        {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ChevronCell", for: indexPath) as! ChevronSettingCell
            cell.label.text = option.title
            cell.chevronImgV.isHidden = (!(option == .biometricsSettings || option == .pinSettings))
            cell.chevronImgV.isHighlighted = expanded.contains(option)
            print("option - \(option) isHighlighted - \(expanded.contains(option))")
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
         
        return 70
     }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        
        let row = indexPath.row
        let option = contents[row]
        
        switch option
        {
        case .did:
            let textToCopy = try! WalletAPI.shared.getDidDocument(type: .HolderDidDocumnet).id
            UIPasteboard.general.string = textToCopy
            PopupUtils.showDialogPopup(title: "DID text was copied.", content: "\(textToCopy)", VC: self)
        case .userAuthentication:
            callSettings(options: [.pinSettings, .biometricsSettings])
        case .pinSettings, .biometricsSettings:
            let subtitles = option.getSubtitles()
            
            if expanded.contains(option)
            {
                expanded.removeAll { $0 == option }
                contents.removeAll { subtitles.contains($0) }
            }
            else
            {
                expanded.append(option)
                contents.append(contentsOf: subtitles)
            }

            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        case .changePIN4Sign:
            let pinVC = UIStoryboard.init(name: "PIN", bundle: nil).instantiateViewController(withIdentifier: "PincodeViewController") as! PincodeViewController
            pinVC.modalPresentationStyle = .fullScreen
            pinVC.setRequestType(type: .change(isLock: false))
            pinVC.changeConfirmButtonCompleteClosure = { oldPasscode, newPasscode in
                do
                {
                    try WalletAPI.shared.changePin(id: KeyIds.pin, oldPIN: oldPasscode, newPIN: newPasscode)
                    
                }
                catch
                {
                    let (title, message) = ErrorHandler.handle(error)
                    
                    print("error code: \(title), message: \(message)")
                    PopupUtils.showAlertPopup(title: title,
                                              content: message,
                                              VC: self)
                }
            }
            pinVC.cancelButtonCompleteClosure = {
                PopupUtils.showAlertPopup(title: "Notification", content: "canceled by user", VC: self)
            }
            DispatchQueue.main.async { self.present(pinVC, animated: false, completion: nil) }
        case .changePIN4Unlock:
            
            if try! !WalletAPI.shared.isLock()
            {
                PopupUtils.showAlertPopup(title: "Notification",
                                          content: "Unlock PIN has not been registered",
                                          VC: self)
                return
            }
            
            let pinVC = UIStoryboard.init(name: "PIN", bundle: nil).instantiateViewController(withIdentifier: "PincodeViewController") as! PincodeViewController
            pinVC.modalPresentationStyle = .fullScreen
            pinVC.setRequestType(type: .change(isLock: true))
            pinVC.changeConfirmButtonCompleteClosure = { oldPasscode, newPasscode in
                
                do
                {
                    try WalletAPI.shared.changeLock(oldPasscode: oldPasscode, newPasscode: newPasscode)
                }
                catch
                {
                    let (title, message) = ErrorHandler.handle(error)
                    
                    print("error code: \(title), message: \(message)")
                    PopupUtils.showAlertPopup(title: title,
                                              content: message,
                                              VC: self)
                }
            }
            pinVC.cancelButtonCompleteClosure = {
                PopupUtils.showAlertPopup(title: "Notification", content: "canceled by user", VC: self)
            }
            DispatchQueue.main.async { self.present(pinVC, animated: false, completion: nil) }
        case .settingBiometrics:
            if try! WalletAPI.shared.isSavedKey(keyId: KeyIds.bio)
            {
                PopupUtils.showAlertPopup(title: "Notification",
                                          content: "Biometrics has already been added",
                                          VC: self)
                return
            }
            
            ActivityUtil.show(vc: self){
                let did = try! WalletAPI.shared.getDidDocument(type: .HolderDidDocumnet).id
                
                try await UpdateUserProtocol.shared.preProcess(did: did)
            } completeClosure: {
                do
                {
                    try WalletAPI.shared.generateKeyPair(hWalletToken: UpdateUserProtocol.shared.hWalletToken,
                                                         keyId: KeyIds.bio,
                                                         algType: .secp256r1,
                                                         promptMsg: "Authenticate to access your private key")
                    
                    
                    let pinVC = UIStoryboard.init(name: "PIN", bundle: nil).instantiateViewController(withIdentifier: "PincodeViewController") as! PincodeViewController
                    pinVC.modalPresentationStyle = .fullScreen
                    pinVC.setRequestType(type: .authenticate(isLock: false))
                    pinVC.confirmButtonCompleteClosure = { passcode in
                        
                        Task { @MainActor in
                            do
                            {
                                try await self.updateDoc(passcode: passcode)
                            }
                            catch
                            {
                                let (title, message) = ErrorHandler.handle(error)
                                
                                print("error code: \(title), message: \(message)")
                                PopupUtils.showAlertPopup(title: title,
                                                          content: message,
                                                          VC: self)
                            }
                        }
                    }
                    pinVC.cancelButtonCompleteClosure = {
                        try! WalletAPI.shared.deleteKeyPair(hWalletToken: UpdateUserProtocol.shared.hWalletToken, keyId: KeyIds.bio)
                        PopupUtils.showAlertPopup(title: "Notification", content: "canceled by user", VC: self)
                    }
                    DispatchQueue.main.async { self.present(pinVC, animated: false, completion: nil) }
                }
                catch
                {
                    let (title, message) = ErrorHandler.handle(error)
                    
                    print("error code: \(title), message: \(message)")
                    PopupUtils.showAlertPopup(title: title,
                                              content: message,
                                              VC: self)
                }
                
                
            } failureCloseClosure: { title, message in
                PopupUtils.showAlertPopup(title: title,
                                          content: message,
                                          VC: self)
            }
            
        default:
            ()
        }
    }
}

extension SettingViewController
{
    func updateDoc(passcode: String) async throws
    {
        ActivityUtil.show(vc: self){
            
            let signedDIDDoc = try WalletAPI.shared.createSignedDIDDoc(passcode: passcode)
            try await UpdateUserProtocol.shared.process(passcode: passcode,
                                                        signedDidDoc: signedDIDDoc)
        } completeClosure: {
            
            
            
        } failureCloseClosure: { title, message in
            try! WalletAPI.shared.deleteKeyPair(hWalletToken: UpdateUserProtocol.shared.hWalletToken, keyId: KeyIds.bio)
            PopupUtils.showAlertPopup(title: title,
                                      content: message,
                                      VC: self)
        }
        
    }
}

extension SettingViewController
{
    func callSettings(options : [TitleOption])
    {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyboard.instantiateViewController(withIdentifier: "SettingViewController") as! SettingViewController
        viewController.contents = options
        self.navigationController?.pushViewController(viewController, animated: true)
    }
    
}

