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

class ZKPSubmissionViewController: UIViewController {

    enum SectionTitleEnum : Int
    {
        case attributes
        case predicates
        case selfAttributes
        
        func getTitle() -> String
        {
            switch self
            {
            case .attributes:
                return "Attributes"
            case .predicates:
                return "Predicates"
            case .selfAttributes:
                return "Self-Attributes"
            }
        }
    }
    
    @IBOutlet weak var descLabel: UILabel!{
        didSet
        {
            let attachment = NSTextAttachment()
            attachment.image = .init(named: "eyeOpen")
            attachment.bounds = .init(origin: CGPoint(x: 0, y: -10), size: CGSizeMake(30, 30))
            
            let imageString = NSAttributedString(attachment: attachment)
            let combined = NSMutableAttributedString(attributedString: imageString)
            combined.append(descLabel.attributedText!)
            
            descLabel.attributedText = combined
        }
    }
    @IBOutlet weak var tableView: UITableView!{
        didSet
        {
            tableView.tableHeaderView = nil
            tableView.tableFooterView = nil
            tableView.contentInsetAdjustmentBehavior = .never
        }
    }
        
    public var zkpSchemas : [String : ZKPCredentialSchema] = [:]
    public var zkpDefs : [String : ZKPCredentialDefinition] = [:]
    public var referentNameMap : [String : String] = [:]
    
    public var availableReferent : AvailableReferent!

    var tempTextField : UnderlinedTextField?
    var tableContentHeight : CGFloat = 0
    
    var selectedIndexMap : [IndexPath : Int] = [:]
    var attrHiddenState : [Int : Bool] = [:]
    var selfRawMap : [Int : String] = [:]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillShow(_:)),
                                               name: UIResponder.keyboardWillShowNotification,
                                               object: nil)
    }

    @IBAction func cancelAction()
    {
        self.dismiss(animated: false, completion: nil)
    }
    
    @IBAction func submitAction()
    {
        Task { @MainActor in
            do {
                let (userReferent, proofParam) = try await makeUserReferent()
                try await submitToVerifier(userReferent: userReferent, proofParam: proofParam)
                
            } catch let error as WalletSDKError {
                print("error code: \(error.code), message: \(error.message)")
                PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
            } catch let error as WalletCoreError {
                print("error code: \(error.code), message: \(error.message)")
                PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
            } catch let error as CommunicationSDKError {
                print("error code: \(error.code), message: \(error.message)")
                PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
            } catch let e as NSError
            {
                
                PopupUtils.showDialogPopup(title: "Error",
                                           content: e.domain,
                                           VC: self)
                
            }
        }
    }
    
    func submitToVerifier(userReferent : [UserReferent], proofParam : ZKProofParam) async throws
    {
        let hWalletToken = try await SDKUtils.createWalletToken(purpose: .PRESENT_VP, userId: Properties.getUserId()!)
        try await VerifyZKProofProtocol().process(hWalletToken: hWalletToken,
                                                  txId: VerifyZKProofProtocol.shared.getTxId(),
                                                  selectedReferents: userReferent,
                                                  proofParam: proofParam,
                                                  proofRequestProfile: VerifyZKProofProtocol.shared.getProofRequestProfile()!)
        
        moveToCompltedView()
        
        
    }
    
    func moveToCompltedView()
    {
        let verifyCompletedVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "VerifyCompletedViewController") as! VerifyCompletedViewController
        verifyCompletedVC.modalPresentationStyle = .fullScreen
        DispatchQueue.main.async {
            self.present(verifyCompletedVC, animated: false, completion: nil)
        }
    }
    
    func makeUserReferent() async throws -> ([UserReferent], ZKProofParam)
    {
        var schemaIds : Set<String> = .init()
        var credDefIds: Set<String> = .init()
        
        var userReferent : [UserReferent] = .init()
        
        for row in 0 ..< availableReferent.attrReferent.count
        {
            let indexPath = IndexPath(row: row,
                                      section: SectionTitleEnum.attributes.rawValue)
            
            let referent = availableReferent.attrReferent[row]
            if let selectedIndex = selectedIndexMap[indexPath]
            {
                let isRevealed = attrHiddenState[row] ?? false
                
                userReferent.append(try! .init(attrReferent: referent,
                                               selectedIndex: UInt(selectedIndex),
                                               isRevealed: isRevealed))
                schemaIds.insert(referent.referent[selectedIndex].schemaId)
                credDefIds.insert(referent.referent[selectedIndex].credDefId)
            }
            else
            {
                throw NSError(domain: "\(SectionTitleEnum.attributes.getTitle())-\(referent.name) is missing selection", code: 1)
            }
        }
        
        for row in 0 ..< availableReferent.predicateReferent.count
        {
            let indexPath = IndexPath(row: row,
                                      section: SectionTitleEnum.predicates.rawValue)
            let referent = availableReferent.predicateReferent[row]
            if let selectedIndex = selectedIndexMap[indexPath]
            {
                
                userReferent.append(try! .init(attrReferent: referent,
                                               selectedIndex: UInt(selectedIndex),
                                               isRevealed: false))
                schemaIds.insert(referent.referent[selectedIndex].schemaId)
                credDefIds.insert(referent.referent[selectedIndex].credDefId)
            }
            else
            {
                throw NSError(domain: "\(SectionTitleEnum.predicates.getTitle())-\(referent.name) is missing selection", code: 1)
            }
        }
        
        for row in 0 ..< availableReferent.selfAttrReferent.count
        {
            let referent = availableReferent.selfAttrReferent[row]
            if let rawValue = selfRawMap[row], rawValue.isEmpty == false
            {
                userReferent.append(.init(raw: rawValue,
                                               referentKey: referent.key,
                                               referentName: referent.name))
            }
        }
        
        var schemas : [String : ZKPCredentialSchema] = .init()
        var defs : [String : ZKPCredentialDefinition] = .init()
        
        for schemaId in schemaIds
        {
            let schema = try await CommnunicationClient.getZKPCredentialSchama(hostUrlString: URLs.API_URL,
                                                                               id: schemaId)
            
            schemas[schemaId] = schema
        }
        
        for credDefId in credDefIds
        {
            let def = try await CommnunicationClient.getZKPCredentialDefinition(hostUrlString: URLs.API_URL,
                                                                                id: credDefId)
            defs[credDefId] = def
        }
        
        let param = ZKProofParam(schemas: schemas,
                                  creDefs: defs)
        
        return (userReferent, param)
    }
}


extension ZKPSubmissionViewController: UITableViewDelegate, UITableViewDataSource
{
    //MARK: Section Header
    func isSectionAvailable(section : Int) -> Bool
    {
        switch SectionTitleEnum(rawValue: section)!
        {
        case .attributes:
            return availableReferent.attrReferent.count > 0
        case .predicates:
            return availableReferent.predicateReferent.count > 0
        case .selfAttributes:
            return availableReferent.selfAttrReferent.count > 0
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        
        if isSectionAvailable(section: section)
        {
            return SectionTitleEnum.init(rawValue: section)!.getTitle()
        }
        
        return nil
    }
    
    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int)
    {
        if !isSectionAvailable(section: section) { return }
            
        if let header = view as? UITableViewHeaderFooterView {
            header.contentView.backgroundColor = .white
            header.textLabel?.textColor = ColorPalette.primary
            header.textLabel?.font = .init(name: "SUIT-Bold", size: 20)
            header.textLabel?.frame.size.width = tableView.frame.width
        }
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat
    {
        return (isSectionAvailable(section: section) ? 50 : 0)
    }
    
    func numberOfSections(in tableView: UITableView) -> Int
    {
        return 3
    }
    
    //MARK: Cell
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch SectionTitleEnum(rawValue: section)!
        {
        case .attributes:
            return availableReferent.attrReferent.count
        case .predicates:
            return availableReferent.predicateReferent.count
        case .selfAttributes:
            return availableReferent.selfAttrReferent.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let section = SectionTitleEnum(rawValue: indexPath.section)!
        let row = indexPath.row
        
        let attrReferent : AttrReferent!
        
        switch section
        {
        case .attributes:
            attrReferent = availableReferent.attrReferent[row]
        case .predicates:
            attrReferent = availableReferent.predicateReferent[indexPath.row]
        case .selfAttributes:
            attrReferent = availableReferent.selfAttrReferent[indexPath.row]
        }
        
        let referentName = referentNameMap[attrReferent.name] ?? attrReferent.name
        
        switch section
        {
        case .attributes, .predicates:
            let cell = tableView.dequeueReusableCell(withIdentifier: "zkpSubmissionCell") as! ZKPSubmissionTableViewCell
            cell.delegate = (section == .attributes) ? self : nil
            cell.eyeBtn.isHidden = (section != .attributes)
            cell.eyeBtn.tag = row
            cell.eyeBtn.isSelected = attrHiddenState[row] ?? false
            
            cell.refNameLabel.text = referentName
            if let selectedIndex = selectedIndexMap[indexPath]
            {
                cell.valueLabel.text = attrReferent.referent[selectedIndex].raw
                cell.valueLabel.textColor = .darkGray
            }
            else
            {
                cell.valueLabel.text = "* Tap to select"
                cell.valueLabel.textColor = .red
            }
            return cell
        case .selfAttributes:
            let cell = tableView.dequeueReusableCell(withIdentifier: "zkpSubmissionTextCell") as! ZKPSubmissionTextTableViewCell
            cell.refNameLabel.text = referentName
            cell.textField.text = selfRawMap[row] ?? ""
            cell.textField.tag = row
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
    {
        tableView.deselectRow(at: indexPath, animated: false)
        
        resignTextField()
        
        let section = SectionTitleEnum(rawValue: indexPath.section)!
        if section == .selfAttributes { return }
        
        moveToSelectionViewController(indexPath: indexPath)
    }
}

extension ZKPSubmissionViewController
{
    func moveToSelectionViewController(indexPath : IndexPath)
    {
        let vc = UIStoryboard(name: "ZKP", bundle: nil).instantiateViewController(withIdentifier: "AttrSelectionViewController") as! AttrSelectionViewController
        
        vc.modalPresentationStyle = .overFullScreen
        
        
        let section = SectionTitleEnum(rawValue: indexPath.section)!
        
        let attrReferent : AttrReferent!
        switch section
        {
        case .attributes:
            attrReferent = availableReferent.attrReferent[indexPath.row]
        case .predicates:
            attrReferent = availableReferent.predicateReferent[indexPath.row]
        case .selfAttributes:
            attrReferent = availableReferent.selfAttrReferent[indexPath.row]
        }
        vc.attrReferent = attrReferent
        vc.indexPath = indexPath
        vc.delegate = self
        vc.zkpSchemas = zkpSchemas
        
        if let value = selectedIndexMap[indexPath]
        {
            vc.selectedIndex = value
        }
        
        DispatchQueue.main.async
        {
            self.present(vc, animated: true, completion: nil)
        }
    }
}

extension ZKPSubmissionViewController : AttrSelectionDelegate
{
    func selectedAttribute(selectedIndex: Int, indexPath: IndexPath)
    {
        selectedIndexMap[indexPath] = selectedIndex
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            tableView.reloadRows(at: [indexPath], with: .none)
        }
    }
    
}

extension ZKPSubmissionViewController : EyeSelectionDelegate
{
    func didSelectEye(isSelected: Bool, index : Int)
    {
        resignTextField()
        
        attrHiddenState[index] = isSelected
        print("\(index) : \(isSelected)")
    }
}


extension ZKPSubmissionViewController : UITextFieldDelegate
{
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool
    {
        tempTextField = textField as? UnderlinedTextField
        
        tempTextField!.underlineColor = .red
        return true
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool
    {
        resignTextField()
        return true
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        print("tag : \(textField.tag)")
        
        selfRawMap[textField.tag] = textField.text!
        
        (textField as? UnderlinedTextField)?.underlineColor = .darkGray
    }
    
    
    func resignTextField()
    {
        guard let textField = tempTextField else { return }
        
        textField.underlineColor = .darkGray
        
        if textField.isFirstResponder
        {
            textField.resignFirstResponder()
        }
    }
}


extension ZKPSubmissionViewController
{
    @objc func keyboardWillShow(_ notification: Notification) {
        if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            let keyboardHeight = keyboardFrame.height
            
            if tableContentHeight == 0
            {
                tableContentHeight = tableView.contentSize.height
            }
            
            tableView.contentSize.height = tableContentHeight + keyboardHeight
            
            guard let tempTextField = tempTextField else { return }
            
            let indexPath = IndexPath(row: tempTextField.tag,
                                      section: SectionTitleEnum.selfAttributes.rawValue)
            
            
            let screenSize = UIScreen.main.bounds
            let keyboardMinY = screenSize.size.height - keyboardHeight
            let rect = tableView.rectForRow(at: indexPath)
            
            let textFieldMaxY = rect.origin.y + tableView.frame.minY + rect.size.height
            
            let overwrapHeight = textFieldMaxY - keyboardMinY
            if overwrapHeight > 0
            {
                tableView.setContentOffset(CGPoint(x: 0, y: overwrapHeight), animated: true)
            }
        }
    }
}
