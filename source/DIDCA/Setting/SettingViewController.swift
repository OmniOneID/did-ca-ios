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

class SettingViewController: UITableViewController {
    
    private var data: [String] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        data = [
                URLs.TAS_URL,
                URLs.VERIFIER_URL,
                (try? WalletAPI.shared.getDidDocument(type: .HolderDidDocumnet).id) ?? ""]
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return data.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "SettingCell") as? SettingCell else {
            return UITableViewCell()
        }
        
        if (indexPath.row == 0) {
            cell.content1?.text = "TAS URL"
        }
        else if (indexPath.row == 1) {
            cell.content1?.text = "Verifier URL"
        }
        else if (indexPath.row == 2) {
            cell.content1?.text = "DID"
        }
        cell.content2?.text = data[indexPath.row]
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        tableView.deselectRow(at: indexPath, animated: true)
        
        if indexPath.row == 2 {
            let textToCopy = data[indexPath.row]
            UIPasteboard.general.string = textToCopy
            PopupUtils.showDialogPopup(title: "DID text was copied.", content: "\(textToCopy)", VC: self)
        }
    }
    
}
