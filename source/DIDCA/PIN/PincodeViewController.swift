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

private enum MessageLevel : String
{
    case register       = "Please register a PIN"
    case registerLock   = "Please register a Unlock PIN"
    case input          = "Please input a PIN"
    case inputLock      = "Please input a Unlock PIN"
    case reEnterPin     = "Please re-enter your PIN"
    case newPin         = "Please input new PIN"
    case notMatchPin    = "PIN does not match"
}

enum PinCodeType
{
    case register(isLock : Bool)
    case authenticate(isLock : Bool)
    case change(isLock : Bool)
}

//register retry count is < 1
//authenticate retry count is < 4

class PincodeViewController: UIViewController
{
    @IBOutlet var inputImgViews: [UIImageView]!
    @IBOutlet weak var messageLbl: UILabel!
    
    var confirmButtonCompleteClosure:((_ passcode: String) -> Void)?
    var changeConfirmButtonCompleteClosure:((_ oldPasscode: String, _ newPasscode: String) -> Void)?
    var cancelButtonCompleteClosure:(()->Void)?
    
    private var securityNumber: String = ""
    
    private var passwordTempValue = ""
    
    private var oldPassword = ""
    
    public var pinCodeType: PinCodeType = .authenticate(isLock: false)
    
    var retryCount : Int = 0
    
    public func setRequestType(type: PinCodeType)
    {
        self.pinCodeType = type
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        updateUI()
    }
        
    private func drawSecurityChar()
    {
        
        for inputImgView in inputImgViews
        {
            inputImgView.image = UIImage(named: inputImgView.tag < securityNumber.count
                                         ? "Pin_num_out"
                                         : "Pin_num_in")
        }
    }
    
    func completeInputted() throws
    {
        if securityNumber.count == 6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Task { @MainActor in
                    try self.completeInputPassword()
                }
            }
        }
    }
    
    private func updateUI()
    {
        switch pinCodeType
        {
        case .register(let isLock):
            self.messageLbl.text = {
                if retryCount == 0
                {
                    return (isLock)
                    ? MessageLevel.registerLock.rawValue
                    : MessageLevel.register.rawValue
                }
                else
                {
                    return MessageLevel.reEnterPin.rawValue
                }
            }()
        case .authenticate(let isLock):
            self.messageLbl.text = (isLock)
            ? MessageLevel.inputLock.rawValue
            : MessageLevel.input.rawValue
        case .change(let isLock):
            if oldPassword.isEmpty
            {
                self.messageLbl.text = (isLock)
                ? MessageLevel.inputLock.rawValue
                : MessageLevel.input.rawValue
            }
            else
            {
                self.messageLbl.text = (retryCount == 0)
                ? MessageLevel.newPin.rawValue
                : MessageLevel.reEnterPin.rawValue
            }
        }
        
        securityNumber = ""
        
        for inputImgView in inputImgViews
        {
            inputImgView.image = UIImage(named: "Pin_num_in")
        }
    }
    
    private func completeInputPassword() throws
    {
        var showNotMatch = true
        switch pinCodeType {
        case .change:
            if oldPassword.isEmpty
            {
                showNotMatch = false
                oldPassword = self.securityNumber
            }
            else{
                fallthrough
            }
        case .register:
            if retryCount == 0
            {
                passwordTempValue = self.securityNumber
                retryCount = 1
                showNotMatch = false
            }
            else
            {
                if passwordTempValue == self.securityNumber
                {
                    self.dismiss(animated: false) {
                        
                        if let change = self.changeConfirmButtonCompleteClosure
                        {
                            change(self.oldPassword, self.securityNumber)
                        }
                        else
                        {
                            self.confirmButtonCompleteClosure?(self.securityNumber)
                        }
                        
                    }
                    return
                }
                else
                {
                    retryCount = 0
                }
            }
        case .authenticate(let isLock):
            if isLock
            {
                if (0...3) ~= retryCount
                {
                    if try WalletAPI.shared.authenticateLock(passcode: self.securityNumber) == nil
                    {
                        retryCount += 1
                    }
                    else
                    {
                        self.dismiss(animated: false) {
                            self.confirmButtonCompleteClosure?(self.securityNumber)
                        }
                        return
                    }
                }
                else
                {
                    retryCount = 0
                    self.dismiss(animated: false) {
                        self.cancelButtonCompleteClosure?()
                    }
                    return
                }
            }
            else
            {
                self.dismiss(animated: false) {
                    self.confirmButtonCompleteClosure?(self.securityNumber)
                }
                return
            }
        }
        
        var delayTime : TimeInterval = 0
        
        if showNotMatch
        {
            self.messageLbl.text = MessageLevel.notMatchPin.rawValue
            delayTime = 1
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delayTime) {
            self.updateUI()
        }
        
    }
    
    @IBAction func onClickButton(_ sender: UIButton)
    {
        if securityNumber.count == 6 { return }
        
        let number = sender.tag
        securityNumber += String(number)
        drawSecurityChar()
        
        do
        {
            try completeInputted()
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
    
    @IBAction func cancelAction()
    {
        self.dismiss(animated: false) {
            self.cancelButtonCompleteClosure?()
        }
    }
    
    @IBAction func deleteAction()
    {
        if securityNumber.isEmpty { return }
        
        securityNumber = String(securityNumber.dropLast())
        
        print(#function)
        print("\(String(describing: securityNumber))")
        
        drawSecurityChar()
    }
    
}
