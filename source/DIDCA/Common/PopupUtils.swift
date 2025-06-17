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

public class PopupUtils {
    static public func showAlertPopup(title:String,
                                      content: String,
                                      VC: UIViewController,
                                      completeClosure : (()->Void)? = nil)
    {
        let popupVC = UIStoryboard.init(name: "Popup", bundle: nil).instantiateViewController(withIdentifier: "ErrorDialogViewController") as! ErrorDialogViewController
        popupVC.modalPresentationStyle = .overCurrentContext
        popupVC.setTitleMessage(message: title)
        popupVC.setContentsMessage(message: content)
        popupVC.confirmButtonCompleteClosure = completeClosure
        DispatchQueue.main.async {
            VC.present(popupVC, animated: false, completion: nil) }
    }
    
    static public func showDialogPopup(title:String, content: String, VC: UIViewController) {
        let popupVC = UIStoryboard.init(name: "Popup", bundle: nil).instantiateViewController(withIdentifier: "OneButtonDialogViewController") as! OneButtonDialogViewController
        popupVC.modalPresentationStyle = .overCurrentContext
        popupVC.setTitleMessage(message: title)
        popupVC.setContentsMessage(message: content)
        popupVC.confirmButtonCompleteClosure = {}
        DispatchQueue.main.async {
            VC.present(popupVC, animated: false, completion: nil) }
    }
    
    static public func showInputPopUp(title: String, subtitle : String, VC: UIViewController, completeClosure : @escaping ((String)->Void))
    {
        let popupVC = UIStoryboard.init(name: "Popup", bundle: nil).instantiateViewController(withIdentifier: "InputPopUpViewController") as! InputPopUpViewController
        popupVC.modalPresentationStyle = .overCurrentContext
        popupVC.setTitleText(titleText: title)
        popupVC.setSubtitleText(subtitleText: subtitle)
        popupVC.confirmButtonCompleteClosure = completeClosure
        
        DispatchQueue.main.async {
            VC.present(popupVC, animated: false, completion: nil) }
    }
}
