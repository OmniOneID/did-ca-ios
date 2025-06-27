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

class InputPopUpViewController: UIViewController {

    @IBOutlet weak var mainView: UIView!
    
    @IBOutlet weak var titleLabel: UILabel!
    {
        didSet
        {
            titleLabel.text = titleText
        }
    }
    
    @IBOutlet weak var subtitleLabel: UILabel!
    {
        didSet
        {
            subtitleLabel.text = subtitleText
        }
    }
    
    @IBOutlet weak var textField: UnderlinedTextField!
    
    var titleText : String = ""
    var subtitleText : String = ""
    
    public var confirmButtonCompleteClosure:((String)->Void)!
//    var cancelButtonCompleteClosure:(()->Void)?
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    
    public func setTitleText(titleText: String)
    {
        self.titleText = titleText
    }
    
    public func setSubtitleText(subtitleText: String)
    {
        self.subtitleText = subtitleText
    }
    
    
    @IBAction func cancelAction()
    {
        self.dismiss(animated: false)
    }
    

    @IBAction func confirmAction()
    {
        confirmButtonCompleteClosure(textField.text ?? "")
        self.dismiss(animated: false)
    }
}

extension InputPopUpViewController : UITextFieldDelegate
{
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool
    {
        (textField as! UnderlinedTextField).underlineColor = .red
        return true
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool
    {
        textField.resignFirstResponder()
        return true
    }
    
    func textFieldDidEndEditing(_ textField: UITextField)
    {
        (textField as! UnderlinedTextField).underlineColor = .darkGray
    }
    
    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        return true
    }
    
}
