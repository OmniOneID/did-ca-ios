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
import DIDUtilitySDK
import DIDDataModelSDK
import DIDCoreSDK
import DIDWalletSDK
import DIDCommunicationSDK

class AddVcViewController: UIViewController {
    
    @IBOutlet weak var vcCollectionView: UICollectionView!
    
    @IBOutlet weak var addDocBtn: UIButton!
    @IBOutlet weak var showQrBtn: UIButton!
    
    private var vcPlans = [VCPlan]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
       
        fatchVcPlanList()
    }
    
    private func fatchVcPlanList() {
        
        Task { @MainActor in
            do {
                let responseData = try await CommnunicationClient().doGet(url: URL(string: URLs.TAS_URL + "/list/api/v1/vcplan/list")!)
                let decodedResponse = try VCPlanList.init(from: responseData)
                vcPlans = decodedResponse.items
                setUpCollectionView()
                
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
    
    private func setUpCollectionView() {
        
//        vcCollectionView.register(AddVCCell.self, forCellWithReuseIdentifier: "AddVCCell")
        vcCollectionView.delegate = self
        vcCollectionView.dataSource = self
        
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 20
        layout.minimumInteritemSpacing = 4
        
        vcCollectionView.setCollectionViewLayout(layout, animated: true)
    }
    
    private func requestVC(qrData: Data) async throws {
            
        let vcOffer = try IssueOfferPayload(from: qrData)
        print("vcOffer JSON: \(try vcOffer.toJson())")
        
        let issueProfileVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "IssueProfileViewController") as! IssueProfileViewController
        issueProfileVC.modalPresentationStyle = .fullScreen
        DispatchQueue.main.async {
            self.present(issueProfileVC, animated: false, completion: nil)
        }
    }
    
    @IBAction func backBtnAction(_ sender: Any) {
        DispatchQueue.main.async {
            self.dismiss(animated: false, completion: nil)
        }
    }
    
    @IBAction func cancelBtnAction(_ sender: Any) {
        
    }
}

extension AddVcViewController: UICollectionViewDataSource {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return vcPlans.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "AddVCCell", for: indexPath) as! AddVCCell

        cell.layer.cornerRadius = 10
        cell.layer.masksToBounds = true
        Task {
            do {
                try await cell.drowVcPlanInfo(data: try vcPlans[indexPath.row].toJsonData())
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
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let vcPlan = vcPlans[indexPath.row]
        let vcSchemaId = vcPlan.credentialSchema.id.components(separatedBy: "=").last!
         
        print("vcPlan: \(try! vcPlan.toJson(isPretty: true))")
        let vcOffer = IssueOfferPayload(type: OfferTypeEnum.IssueOffer, vcPlanId: vcPlan.vcPlanId, issuer: vcPlan.allowedIssuers![0])
        print("vcOffer JSON: \(try! vcOffer.toJson())")
        
        let issueProfileVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "IssueProfileViewController") as! IssueProfileViewController
        issueProfileVC.vcSchemaId = vcSchemaId
        issueProfileVC.setVcOffer(vcOfferPayload: vcOffer, isWebView: true)
        issueProfileVC.modalPresentationStyle = .fullScreen
        DispatchQueue.main.async {
            self.present(issueProfileVC, animated: false, completion: nil)
        }
    }
}

extension AddVcViewController: UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView,
                  layout collectionViewLayout: UICollectionViewLayout,
                  insetForSectionAt section: Int) -> UIEdgeInsets {

        return UIEdgeInsets(top: 10.0, left: 13.0, bottom: 10.0, right: 13.0)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let lay = collectionViewLayout as! UICollectionViewFlowLayout
        let widthPerItem = collectionView.frame.width / 2 - lay.minimumInteritemSpacing
        
        return CGSize(width: widthPerItem - 20, height: 200)
    }
}
