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

protocol AttrSelectionDelegate
{
    func selectedAttribute(selectedIndex: Int, indexPath: IndexPath)
}

class AttrSelectionViewController: UIViewController {
    
    @IBOutlet weak var refNameLabel: UILabel!{
        didSet{
            refNameLabel.text = attrReferent.name
        }
    }
    
    @IBOutlet weak var tableView: UITableView!
    
    public var zkpSchemas : [String : ZKPCredentialSchema] = [:]
    public var vcStatus: [String : VCStatusEnum]!
    
//    public var selectedIndex : Int = -1
    public var attrReferent : AttrReferent!
    public var indexPath : IndexPath!
    public var delegate : AttrSelectionDelegate?
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
    }
    
//    @IBAction func cancelAction()
//    {
//        self.dismiss(animated: true)
//    }
    
//    @IBAction func okAction()
//    {
////        if selectedIndex == -1 { return }
//        
//        self.dismiss(animated: true)
//        {
//            DispatchQueue.main.async {
//                self.delegate?.selectedAttribute(selectedIndex: self.selectedIndex,
//                                                 indexPath: self.indexPath)
//            }
//        }
//    }
    
}

extension AttrSelectionViewController: UITableViewDelegate, UITableViewDataSource
{
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return attrReferent.referent.count
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let subReferent = attrReferent.referent[indexPath.row]
        return (vcStatus[subReferent.credId] != .ACTIVE)
        ? 0
        : 80
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let subReferent = attrReferent.referent[indexPath.row]
        if vcStatus[subReferent.credId] != .ACTIVE
        {
            return UITableViewCell()
        }
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "attrSelectionCell") as! AttrSelectionTableViewCell
//        cell.changeBorderColor(isSelected: selectedIndex == indexPath.row)
        
        
        cell.nameLabel.text = zkpSchemas[subReferent.schemaId]?.name ?? "Unknown name"
        cell.valueLabel.text = subReferent.raw
        
        return cell
        
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
//        selectedIndex = indexPath.row
        
//        tableView.reloadData()
        self.dismiss(animated: true)
        {
            DispatchQueue.main.async {
                self.delegate?.selectedAttribute(selectedIndex: indexPath.row,
                                                 indexPath: self.indexPath)
            }
        }
    }
}
