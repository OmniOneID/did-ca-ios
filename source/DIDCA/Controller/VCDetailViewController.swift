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
            zkpCaptionDict = zkpSchema!.attrTypes
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
            do
            {
                try await RevokeVcProtocol.shared.preProcess(vcId: vc!.id)
            }
            catch let error as WalletSDKError
            {
                print("error code: \(error.code), message: \(error.message)")
                PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
            }
            catch let error as WalletCoreError
            {
                print("error code: \(error.code), message: \(error.message)")
                PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
            }
            catch let error as CommunicationSDKError
            {
                print("error code: \(error.code), message: \(error.message)")
                PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
            }
            catch let e as NSError
            {
                PopupUtils.showDialogPopup(title: "Error",
                                           content: e.domain,
                                           VC: self)
            }
                
            do {
                _ = try WalletAPI.shared.getKeyInfos(ids: ["pin","bio"])
                
                let selectAuthVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "SelectAuthViewController") as! SelectAuthViewController
                selectAuthVC.setCommandType(command: 0)
                selectAuthVC.modalPresentationStyle = .fullScreen
                DispatchQueue.main.async { self.present(selectAuthVC, animated: false, completion: nil) }
            } catch {
                let pinVC = UIStoryboard.init(name: "PIN", bundle: nil).instantiateViewController(withIdentifier: "PincodeViewController") as! PincodeViewController
                pinVC.modalPresentationStyle = .fullScreen
                pinVC.setRequestType(type: PinCodeTypeEnum.PIN_CODE_AUTHENTICATION_SIGNATURE_TYPE)
                pinVC.confirmButtonCompleteClosure = { [self] passcode in
                    Task { @MainActor in
                        do {
                            _ = try await RevokeVcProtocol.shared.process(passcode: passcode)
                            
                            let mainVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "MainViewController") as! MainViewController
                            mainVC.modalPresentationStyle = .fullScreen
                            DispatchQueue.main.async {
                                self.present(mainVC, animated: false, completion: nil)
                            }
                        } catch let error as WalletSDKError {
                            print("error code: \(error.code), message: \(error.message)")
                            PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
                        } catch let error as WalletCoreError {
                            print("error code: \(error.code), message: \(error.message)")
                            PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
                        } catch let error as CommunicationSDKError {
                            print("error code: \(error.code), message: \(error.message)")
                            PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
                        } catch {
                            print("error :\(error)")
                        }
                    }
                }
                pinVC.cancelButtonCompleteClosure = {
                    PopupUtils.showAlertPopup(title: "Notification", content: "canceled by user", VC: self)
                }
                DispatchQueue.main.async { self.present(pinVC, animated: false, completion: nil) }
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
//            header.contentView.directionalLayoutMargins = .zero
            header.preservesSuperviewLayoutMargins = false
            header.contentView.layoutMargins = .zero
            
            header.textLabel?.textColor = ColorPalette.primary
            header.textLabel?.font = .init(name: "SUIT-Bold", size: 20)
            header.textLabel?.frame.size.width = tableView.frame.width
            header.textLabel?.frame.origin.x = 0
            header.textLabel?.textAlignment = .left
            
        }
        
//        guard let header = view as? UITableViewHeaderFooterView else { return }
//        header.contentView.backgroundColor = .white
//        
//        var config = UIListContentConfiguration.plainHeader()
//        config.text = SectionTitleEnum.init(rawValue: section)!.getTitle()
//        config.textProperties.font = .init(name: "SUIT-Bold", size: 20)!
//        config.textProperties.color = ColorPalette.primary
//        
//        
//        header.contentConfiguration = config
        
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
                let image = try! SDKUtils.generateImg(base64String: claim.value)
                let targetSize = CGSize(width: 100, height: 100)
                UIGraphicsBeginImageContextWithOptions(targetSize, false, 0.0)
                image.draw(in: CGRect(origin: .zero, size: targetSize))
                let newImage = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                
                let cell = tableView.dequeueReusableCell(withIdentifier: "imageCell") as! VCDetailImageTableViewCell
                cell.captionLabel.text = claim.caption
                cell.claimImageView.image = newImage
                
                return cell
            }
            else
            {
                let cell = tableView.dequeueReusableCell(withIdentifier: "stringCell") as! VCDetailStringTableViewCell
                cell.captionLabel.text = claim.caption
                cell.valueLabel.text = claim.value
                
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
                                        
