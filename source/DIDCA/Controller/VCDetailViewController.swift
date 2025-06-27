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

class VCDetailViewController: UIViewController {
    
    enum SectionTitleEnum : Int
    {
        case verifiableCredential
        case zkp
        
        func getTitle() -> String
        {
            switch self
            {
            case .verifiableCredential:
                return "Verifiable Credential"
            case .zkp:
                return "Zero-Knowledge Proof"
            }
        }
    }
    
    weak var delegate: DismissDelegate?
    
    @IBOutlet var tableViewHeader: UIView!
    
    @IBOutlet weak var tableView: UITableView!
    {
        didSet{
            tableView.tableHeaderView = tableViewHeader
        }
    }
    @IBOutlet weak var vcStatusLabel: RoundedLabel!{
        didSet{
            Task { @MainActor in
                self.vcStatusLabel.text = try await VCStatusGetter.getStatus(vcId: vc!.id).rawValue
            }
        }
    }
    
    @IBOutlet weak var nameLbl: UILabel!{
        didSet{
            nameLbl.text = Properties.getUserName()
        }
    }
    
    private var zkpCaptionDict : [String : String] = [:]
    private var vc: VerifiableCredential? = nil
    private var zkpVC : ZKPCredential? = nil
    private var zkpSchema : ZKPCredentialSchema? = nil
    {
        didSet
        {
            guard let zkpSchema = zkpSchema else { return }
            zkpCaptionDict = zkpSchema.attrTypes
                .flatMap { attr in
                    attr.items.map { item in
                        (attr.namespace.id + "." + item.label, item.caption)
                    }
                }
                .reduce(into: [String: String]()) { dict, pair in
                    dict[pair.0] = pair.1
                }
            
        }
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
    }
    
    public func setVcInfo(vc: VerifiableCredential,
                          zkpVC : ZKPCredential?,
                          zkpSchema : ZKPCredentialSchema?)
    {
        self.vc = vc
        self.zkpVC = zkpVC
        self.zkpSchema = zkpSchema
    }
    
    @IBAction func continueAction() {
        self.dismiss(animated: false, completion: nil)
    }
    
    
    @IBAction func deleteAction()
    {
        Task { @MainActor in
            let status = try await VCStatusGetter.getStatus(vcId: vc!.id)
            
            if status == .REVOKED
            {
                ActivityUtil.show(vc: self){
                    let hWalletToken = try await SDKUtils.createWalletToken(purpose: .REMOVE_VC,
                                                                            userId: Properties.getUserId()!)
                    _ = try WalletAPI.shared.deleteCredentials(hWalletToken: hWalletToken,
                                                               ids: [self.vc!.id])
                } completeClosure: {
                    self.dismiss(animated: false)
                } failureCloseClosure: { title, message in
                    PopupUtils.showAlertPopup(title: title,
                                              content: message,
                                              VC: self)
                }
                
            }
            else{
                ActivityUtil.show(vc: self){
                    try await RevokeVcProtocol.shared.preProcess(vcId: self.vc!.id)
                } completeClosure: {
                    SelectAuthHelper.show(on: self) { passcode in
                        //
                        ActivityUtil.show(vc: self){
                            _ = try await RevokeVcProtocol.shared.process(passcode: passcode)
                        } completeClosure: {
                            self.dismiss(animated: false)
                        } failureCloseClosure: { title, message in
                            PopupUtils.showAlertPopup(title: title,
                                                      content: message,
                                                      VC: self)
                        }
                    } cancelClosure: {
                        PopupUtils.showAlertPopup(title: "Notification",
                                                  content: "canceled by user",
                                                  VC: self)
                    }
                } failureCloseClosure: { title, message in
                    PopupUtils.showAlertPopup(title: title,
                                              content: message,
                                              VC: self)
                }
            }
        }
    }
}

extension VCDetailViewController: UITableViewDelegate, UITableViewDataSource
{
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        
        return SectionTitleEnum.init(rawValue: section)!.getTitle()
    }
    
    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int)
    {
        if let header = view as? UITableViewHeaderFooterView {
            header.contentView.backgroundColor = .white
            header.preservesSuperviewLayoutMargins = false
            header.contentView.layoutMargins = .zero
            
            header.textLabel?.textColor = ColorPalette.primary
            header.textLabel?.font = .init(name: "SUIT-Bold", size: 20)
            header.textLabel?.frame.size.width = tableView.frame.width
            header.textLabel?.frame.origin.x = 0
            header.textLabel?.textAlignment = .left
            
        }
        
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat
    {
        return 40
    }
    
    func numberOfSections(in tableView: UITableView) -> Int
    {
        return (zkpVC != nil) ? 2 : 1
    }
    
    //MARK: Cell
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch SectionTitleEnum(rawValue: section)!
        {
        case .verifiableCredential:
            return vc!.credentialSubject.claims.count
        case .zkp:
            return zkpVC!.values.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let section = SectionTitleEnum(rawValue: indexPath.section)!
        let row = indexPath.row
        
        switch section
        {
        case .verifiableCredential:
            
            let claim = vc!.credentialSubject.claims[row]
            
            if claim.type == .image
            {
                let cell = tableView.dequeueReusableCell(withIdentifier: "imageCell") as! VCDetailImageTableViewCell
                cell.captionLabel.text    = claim.caption
                cell.claimImageView.image = try! ImageUtils.generateImg(base64String: claim.value,
                                                                   targetSize: CGSize(width: 100, height: 100))

                return cell
            }
            else
            {
                let cell = tableView.dequeueReusableCell(withIdentifier: "stringCell") as! VCDetailStringTableViewCell
                cell.captionLabel.text = claim.caption
                cell.valueLabel.text   = claim.value
                
                return cell
            }
            
            
        case .zkp:
            let cell = tableView.dequeueReusableCell(withIdentifier: "stringCell") as! VCDetailStringTableViewCell
            
            let keys = Array(zkpVC!.values.keys).sorted()
            let key = keys[row]
            
            cell.captionLabel.text = zkpCaptionDict[key] ?? key
            cell.valueLabel.text = zkpVC!.values[key]!.raw
            
            return cell
        }
        
    }
}
