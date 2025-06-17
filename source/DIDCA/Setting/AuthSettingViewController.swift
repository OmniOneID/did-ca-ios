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




class AuthSettingViewController: UITableViewController {
    
    private var data: [String] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        data = [
                "Change PIN for Signing",
                "Change PIN for Unlock",
                "Setting up a fingerprint for Signing",
                "Setting up a fingerprint for Unlock"
                ]
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return data.count
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {

        return 70
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "SettingCell") as? SettingCell else {
            return UITableViewCell()
        }
        
        cell.content1?.text = data[indexPath.row]
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.row == 0 {
            let pinVC = UIStoryboard.init(name: "PIN", bundle: nil).instantiateViewController(withIdentifier: "PincodeViewController") as! PincodeViewController
            pinVC.modalPresentationStyle = .fullScreen
            pinVC.setRequestType(type: .authenticate(isLock: false))
            pinVC.confirmButtonCompleteClosure = { [self] passcode in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    Task { @MainActor in
                        self.regPIN(oldPIN: passcode)
                    }
                }
            }
            pinVC.cancelButtonCompleteClosure = {
                PopupUtils.showAlertPopup(title: "Notification", content: "canceled by user", VC: self)
            }
            DispatchQueue.main.async { self.present(pinVC, animated: false, completion: nil) }
        }
    }
    
    private func regPIN(oldPIN: String) {
        
        let pinVC = UIStoryboard.init(name: "PIN", bundle: nil).instantiateViewController(withIdentifier: "PincodeViewController") as! PincodeViewController
        pinVC.modalPresentationStyle = .fullScreen
        pinVC.setRequestType(type: .change)
        pinVC.confirmButtonCompleteClosure = { [self] passcode in
            
            do {
                try WalletAPI.shared.changePin(id: "pin", oldPIN: oldPIN, newPIN: passcode)
            } catch let error as WalletSDKError {
                print("error code: \(error.code), message: \(error.message)")
                PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
            } catch let error as WalletCoreError {
                print("error code: \(error.code), message: \(error.message)")
                PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
            } catch {
                print("error :\(error)")
            }
        }
        pinVC.cancelButtonCompleteClosure = {
            PopupUtils.showAlertPopup(title: "Notification", content: "canceled by user", VC: self)
        }
        DispatchQueue.main.async { self.present(pinVC, animated: true, completion: nil) }
    }
}
