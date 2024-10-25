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
import DIDUtilitySDK
import DIDWalletSDK
import DIDCommunicationSDK
import DIDDataModelSDK

class IssueCompletedViewController: UIViewController {
 
    @IBOutlet weak var comfirmBtn: UIButton!
    @IBOutlet weak var userNameLbl: UILabel!
    @IBOutlet weak var userImage: UIImageView!
    
    @IBOutlet weak var completedInfoDescLbl: UILabel!
    
    @IBAction func confirmBtnAction(_ sender: Any) {
        let submitVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "MainViewController") as! MainViewController
        submitVC.modalPresentationStyle = .fullScreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.present(submitVC, animated: false, completion: nil)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        userNameLbl.text = Properties.getUserName()
        completedInfoDescLbl.text = "you can now add your "+(IssueVcProtocol.shared.getIssueProfile()?.profile.title)!
    }
}
