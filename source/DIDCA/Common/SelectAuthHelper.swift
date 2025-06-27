//
/*
 * Copyright 2025 OmniOne.
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

struct SelectAuthHelper
{
    static func show(on viewController: UIViewController,
                     completeClosure : @escaping ((_ passcode: String?) -> Void),
                     cancelClosure: @escaping (()->Void))
    {
        do {
            _ = try WalletAPI.shared.getKeyInfos(ids: ["pin","bio"])
            try BiometricAuthenticator.canEvaluatePolicy()
            
            showSelectAuth(on: viewController,
                           completeClosure: completeClosure,
                           cancelClosure: cancelClosure)
        } catch {
            showPin(on: viewController,
                    completeClosure: completeClosure,
                    cancelClosure: cancelClosure)
        }
    }
    
    private static func showSelectAuth(on viewController: UIViewController,
                                       completeClosure :  @escaping ((_ passcode: String?) -> Void),
                                       cancelClosure:  @escaping (()->Void))
    {
        let selectAuthVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "SelectAuthViewController") as! SelectAuthViewController
        selectAuthVC.confirmButtonCompleteClosure = completeClosure
        selectAuthVC.cancelButtonCompleteClosure = cancelClosure
        
        let navi = UINavigationController(rootViewController: selectAuthVC)
        navi.isNavigationBarHidden = true
        navi.modalPresentationStyle = .fullScreen
        
        DispatchQueue.main.async {
            viewController.present(navi, animated: false)
        }
    }
    
    private static func showPin(on viewController: UIViewController,
                                completeClosure : @escaping ((_ passcode: String?) -> Void),
                                cancelClosure:@escaping (()->Void))
    {
        let pinVC = UIStoryboard.init(name: "PIN", bundle: nil).instantiateViewController(withIdentifier: "PincodeViewController") as! PincodeViewController
        pinVC.modalPresentationStyle = .fullScreen
        pinVC.setRequestType(type: .authenticate(isLock: false))
        pinVC.confirmButtonCompleteClosure = completeClosure
        pinVC.cancelButtonCompleteClosure = cancelClosure
        
        DispatchQueue.main.async
        {
            viewController.present(pinVC, animated: false, completion: nil)
        }
    }
    
}
