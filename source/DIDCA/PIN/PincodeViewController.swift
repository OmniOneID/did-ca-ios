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



public enum PinCodeTypeEnum: Int {
    case PIN_CODE_UNKNOWN = -1
    case PIN_CODE_REGISTRATION_LOCK_TYPE = 0
    case PIN_CODE_AUTHENTICATION_LOCK_TYPE
    case PIN_CODE_REGISTRATION_SIGNATURE_TYPE
    case PIN_CODE_AUTHENTICATION_SIGNATURE_TYPE
    case PIN_CODE_CHANGE_SIGNATURE_TYPE
}

class PincodeViewController: UIViewController {
    
    @IBOutlet weak var img1: UIImageView!
    @IBOutlet weak var img2: UIImageView!
    @IBOutlet weak var img3: UIImageView!
    @IBOutlet weak var img4: UIImageView!
    @IBOutlet weak var img5: UIImageView!
    @IBOutlet weak var img6: UIImageView!
    
    @IBOutlet weak var deleteBtn: UIButton!
    @IBOutlet weak var cancelBtn: UIButton!
    @IBOutlet weak var messageLbl: UILabel!
    
    var confirmButtonCompleteClosure:((_ passcode: String) -> Void)?
    var cancelButtonCompleteClosure:(()->Void)?
    
    private var securityNumber: String! = ""
    
    private var requestType: PinCodeTypeEnum = PinCodeTypeEnum.PIN_CODE_UNKNOWN
    
    private var passwordCnt: Int = 0
    private var passwordTempValue = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if requestType == .PIN_CODE_CHANGE_SIGNATURE_TYPE {
            self.messageLbl.text = "Please input new PIN"
        }
    }
    
    public func setRequestType(type: PinCodeTypeEnum) {
        self.requestType = type
    }
    
    public func getRequestType() -> PinCodeTypeEnum {
        return requestType
    }
    
    private func deleteNumber() throws {
        
        if securityNumber.count > 1 {
            securityNumber = String(securityNumber.dropLast())
        } else if securityNumber.count == 1 {
            securityNumber = ""
        }
        try drowSecurityChar()
    }
    
    private func cancelNumber() {
        if let cancelButtonCompleteClosure = cancelButtonCompleteClosure {
            cancelButtonCompleteClosure()
            self.dismiss(animated: false, completion: nil)
        }
    }
    
    private func drowSecurityChar() throws {
        
        let images = (0..<6).map { index -> UIImage? in
            return UIImage(named: index < securityNumber.count ? "Pin_num_out" : "Pin_num_in")
        }
        
        img1.image = images[0]
        img2.image = images[1]
        img3.image = images[2]
        img4.image = images[3]
        img5.image = images[4]
        img6.image = images[5]
        
        if securityNumber.count == 6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Task { @MainActor in
                    try self.completeInputPassword(passcode: self.securityNumber)
                }
            }
        }
    }
    
    private func resetWithUI() {
        securityNumber = ""
        
        img1.image = UIImage(named: "Pin_num_in")
        img2.image = UIImage(named: "Pin_num_in")
        img3.image = UIImage(named: "Pin_num_in")
        img4.image = UIImage(named: "Pin_num_in")
        img5.image = UIImage(named: "Pin_num_in")
        img6.image = UIImage(named: "Pin_num_in")
    }
    
    private func lockReg(passcode: String) -> Void {
        print("passwordCnt: \(passwordCnt)")
        print("passwordTempValue: \(passwordTempValue)")
        
        switch passwordCnt {
        case 0:
            passwordTempValue = String(passcode)
            passwordCnt += 1
            self.messageLbl.text = "Please re-enter your PIN"
            resetWithUI()
            break
        case 1:
            if passwordTempValue == passcode {
                if let confirmButtonCompleteClosure = confirmButtonCompleteClosure {
                    confirmButtonCompleteClosure(passcode)
                    self.dismiss(animated: false, completion: nil)
                }
            } else {
                self.messageLbl.text = "PIN does not match"
                resetWithUI()
            }
            passwordCnt = 0
            passwordTempValue = ""
            break
        default:
            break
        }
    }
    
    private func lockAuth(passcode: String) throws {
        switch passwordCnt {
        case 0...3:
            if try WalletAPI.shared.authenticateLock(passcode: passcode) == nil {
                passwordCnt += 1
                
                self.messageLbl.text = "PIN does not match"
                resetWithUI()
                
            } else {
                passwordCnt = 0
                if let confirmButtonCompleteClosure = confirmButtonCompleteClosure {
                    confirmButtonCompleteClosure(passcode)
                    self.dismiss(animated: false, completion: nil)
                }
            }
            break
        case 4:
            passwordCnt = 0
            if let cancelButtonCompleteClosure = cancelButtonCompleteClosure {
                cancelButtonCompleteClosure()
                self.dismiss(animated: false, completion: nil)
            }
            break
        default:
            break;
        }
    }
    
    private func regSignature(passcode: String) {
        print("passwordCnt: \(passwordCnt)")
        print("passwordTempValue: \(passwordTempValue)")
        switch passwordCnt {
        case 0:
            passwordTempValue = String(passcode)
            passwordCnt += 1
            self.messageLbl.text = "Please re-enter your PIN"
            resetWithUI()
            break
        case 1:
            if passwordTempValue == passcode {
                //키쌍 생성 및 VC발급
                if let confirmButtonCompleteClosure = confirmButtonCompleteClosure {
                    confirmButtonCompleteClosure(passcode)
                    self.dismiss(animated: false, completion: nil)
                }
            } else {
                self.messageLbl.text = "PIN does not match"
                resetWithUI()
            }
            passwordCnt = 0
            passwordTempValue = ""
            break
        default:
            break
        }
    }
    
    private func authSignature(passcode: String) {
        switch passwordCnt {
        case 0...3:
            passwordCnt = 0
            if let confirmButtonCompleteClosure = confirmButtonCompleteClosure {
                confirmButtonCompleteClosure(passcode)
                self.dismiss(animated: false, completion: nil)
            }
            break
        case 4:
            passwordCnt = 0
            if let cancelButtonCompleteClosure = cancelButtonCompleteClosure {
                cancelButtonCompleteClosure()
                self.dismiss(animated: false, completion: nil)
            }
            break
        default:
            break;
        }
    }
    
    private func changeSignature(passcode: String) {
        print("passwordCnt: \(passwordCnt)")
        print("passwordTempValue: \(passwordTempValue)")
        switch passwordCnt {
        case 0:
            passwordTempValue = String(passcode)
            passwordCnt += 1
            self.messageLbl.text = "Please re-enter your PIN"
            resetWithUI()
            break
        case 1:
            if passwordTempValue == passcode {
                if let confirmButtonCompleteClosure = confirmButtonCompleteClosure {
                    confirmButtonCompleteClosure(passcode)
                    self.dismiss(animated: false, completion: nil)
                }
            } else {
                self.messageLbl.text = "PIN does not match"
                resetWithUI()
            }
            passwordCnt = 0
            passwordTempValue = ""
            break
        default:
            break
        }
    }
    
    
    private func completeInputPassword(passcode: String) throws {
        
        switch self.requestType {
        case .PIN_CODE_REGISTRATION_LOCK_TYPE:
            print("reg")
            lockReg(passcode: passcode)
            break
        case .PIN_CODE_AUTHENTICATION_LOCK_TYPE:
            print("auth")
            try lockAuth(passcode: passcode)
            break
        case .PIN_CODE_REGISTRATION_SIGNATURE_TYPE:
            print("reg signature")
            regSignature(passcode: passcode)
            break;
        case .PIN_CODE_AUTHENTICATION_SIGNATURE_TYPE:
            print("auth signature")
            authSignature(passcode: passcode)
            break;
        case .PIN_CODE_CHANGE_SIGNATURE_TYPE:
            print("change signature")
            changeSignature(passcode: passcode)
            break;
        default:
            break
        }
    }
    
    @IBAction func onClickButton(_ sender: UIButton) {
        
        do {
            if sender.tag == -1 {
                try deleteNumber()
            } else if sender.tag == -2 {
                cancelNumber()
            } else {
                if let title = sender.currentTitle, let number = Int(title) {
                    if securityNumber.count == 6 { return }
                    securityNumber += String(number)
                    try drowSecurityChar()
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
