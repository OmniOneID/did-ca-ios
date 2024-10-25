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

class OneButtonDialogViewController: UIViewController {
    
    @IBOutlet weak var confirmButton: UIButton!
    @IBOutlet weak var contentsLbl: UILabel!
    private var contentsMessage = ""
    @IBOutlet weak var titleLbl: UILabel!
    private var titleMessage = ""
    
    
    var confirmButtonCompleteClosure:(()->Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.layer.cornerRadius = 10
        
        if self.titleLbl != nil {
            self.titleLbl.text = titleMessage
        }
        if self.contentsLbl != nil {
            self.contentsLbl.text = contentsMessage
        }
    }
    
    @IBAction func confirmButtonAction(_ sender: Any) {
        if let confirmButtonCompleteClosure = confirmButtonCompleteClosure {
            confirmButtonCompleteClosure()
            self.dismiss(animated: false, completion: nil)
        }
    }
    
    public func setContentsMessage(message: String) {
        self.contentsMessage = message
    }
    
    public func setTitleMessage(message: String) {
        self.titleMessage = message
    }
}
