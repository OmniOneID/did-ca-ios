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

class SelectAuthViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    enum AuthTypeEnum : String
    {
        case pin = "PIN"
        case bio = "BIO"
    }
    
    private var list : [AuthTypeEnum] = [.pin, .bio]
    
    var confirmButtonCompleteClosure:((_ passcode: String?) -> Void)!
    var cancelButtonCompleteClosure:(()->Void)!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    @IBAction func cancelBtnAction(_ sender: Any) {
        DispatchQueue.main.async {
            self.dismiss(animated: false, completion: nil)
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
        
        let authTypeEnum = list[indexPath.row]
        
        cell.textLabel?.text = authTypeEnum.rawValue
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 100
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let authTypeEnum = list[indexPath.row]
        
        if authTypeEnum == .pin
        {
            showPin()
        }
        else
        {
            showBio()
        }
    }
}

extension SelectAuthViewController
{
    func showPin()
    {
        let pinVC = UIStoryboard.init(name: "PIN", bundle: nil).instantiateViewController(withIdentifier: "PincodeViewController") as! PincodeViewController
        pinVC.modalPresentationStyle = .fullScreen
        pinVC.setRequestType(type: .authenticate(isLock: false))
        pinVC.confirmButtonCompleteClosure = confirmButtonCompleteClosure
        pinVC.cancelButtonCompleteClosure = cancelButtonCompleteClosure
        
        DispatchQueue.main.async {
            self.navigationController?.pushViewController(pinVC, animated: false)
        }
    }
    
    func showBio()
    {
        DispatchQueue.main.async {
            self.dismiss(animated: false) {
                self.confirmButtonCompleteClosure?(nil)
            }
        }
        
    }
}
