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


import DIDWalletSDK



class MainViewController: UIViewController, DismissDelegate {
    @IBOutlet weak var vcCollectionView: UICollectionView!
    @IBOutlet weak var userInfoLbl: UILabel!
    @IBOutlet weak var addDocBtn: UIButton!
    @IBOutlet weak var showQrBtn: UIButton!
    @IBOutlet weak var vcDescLbl: UILabel!
    private var vcs = [VerifiableCredential]()
    
    func didDidmissWithData() {
        showUI()
    }
    
    func showUI() {
        Task { @MainActor in
            do {
                userInfoLbl.text = Properties.getUserName()
                
                let hWalletToken = try await SDKUtils.createWalletToken(purpose: WalletTokenPurposeEnum.LIST_VC, userId: Properties.getUserId()!)
                
                if let credentials = try WalletAPI.shared.getAllCrentials(hWalletToken: hWalletToken) {
                    vcs = credentials
                    
                    let didDoc = try WalletAPI.shared.getDidDocument(type: DidDocumentType.HolderDidDocumnet)
                    print("holderDidDoc : \(try didDoc.toJson(isPretty: true))")
                    
                    print("vcs: \(vcs.count)")
                    for vc in vcs {
                        print("vc: \(try! vc.toJson())")
                    }
                    setUpCollectionView()
                    return
                }
                
                self.vcCollectionView.isHidden = true
        
                vcDescLbl.layer.cornerRadius = 5
                vcDescLbl.layer.borderColor = UIColor.black.cgColor
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
  
    override func viewDidLoad() {
        super.viewDidLoad()
        addDocBtn.layer.borderWidth = 1
        addDocBtn.layer.borderColor = UIColor(hexCode: "FF8400").cgColor
        Properties.setSubmitCompleted(status: true)
        showUI()
    }
    
    private func setUpCollectionView() {
        
//        vcCollectionView.register(VCCell.self, forCellWithReuseIdentifier: "VCCell")
        vcCollectionView.delegate = self
        vcCollectionView.dataSource = self
        
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 20
        layout.minimumInteritemSpacing = 4
        
        vcCollectionView.setCollectionViewLayout(layout, animated: true)
    }
    
    private func requestVP(qrData: Data) async throws {
        let vpOffer = try VerifyOfferPayload(from: qrData)
        print("vpOffer JSON: \(try vpOffer.toJson())")
        
        let verifyProfileVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "VerifyProfileViewController") as! VerifyProfileViewController
        verifyProfileVC.modalPresentationStyle = .fullScreen
        verifyProfileVC.setVpOffer(vpOffer: vpOffer)
        DispatchQueue.main.async {
            self.present(verifyProfileVC, animated: false, completion: nil)
        }
    }
    
    private func requestVC(qrData: Data) async throws {
        let vcOffer = try IssueOfferPayload(from: qrData)
        print("vcOffer JSON: \(try vcOffer.toJson())")
        
        let issueProfileVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "IssueProfileViewController") as! IssueProfileViewController
        issueProfileVC.setVcOffer(vcOfferPayload: vcOffer)
        issueProfileVC.modalPresentationStyle = .fullScreen
        DispatchQueue.main.async {
            self.present(issueProfileVC, animated: false, completion: nil)
        }
    }
    
    @IBAction func showQrBtnAction(_ sender: Any) {
        let qrVC = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "QRScanViewController") as! QRScanViewController
        qrVC.delegate = self
        qrVC.modalPresentationStyle = .popover

        DispatchQueue.main.async {
            self.present(qrVC, animated: false, completion: nil)
        }
    }
}

extension MainViewController: ScanQRViewControllerDelegate {
    func extractStringfromQRCode(qrString: String) {
        Task {
            do {
                let dataPayload = try DataPayload.init(from: qrString)
                let payload = try MultibaseUtils.decode(encoded: dataPayload.payload)
                print("payload json: \(try dataPayload.toJson())")
                print("payload: \(dataPayload.payload)")
                print("payloadType: \(dataPayload.payloadType)")
                
                if dataPayload.payloadType == "ISSUE_VC" {
                    try await requestVC(qrData: payload)
                } else {
                    try await requestVP(qrData: payload)
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
}
extension MainViewController: UICollectionViewDataSource {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return vcs.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "VCCell", for: indexPath) as! VCCell

        cell.layer.cornerRadius = 10
        cell.layer.masksToBounds = true
        DispatchQueue.main.async { [self] in
            Task {
                do {
                    // http://192.168.3.130:8093/api-gateway/api/v1/vc-meta
                    try await cell.drowVcInfo(data: try vcs[indexPath.row].toJsonData(), type: indexPath.row)
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
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        let detialVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "VCDetailViewController") as! VCDetailViewController
        detialVC.modalPresentationStyle = .fullScreen
        
        Task { @MainActor in
            let hWalletToken = try await SDKUtils.createWalletToken(purpose: WalletTokenPurposeEnum.DETAIL_VC, userId: Properties.getUserId()!)
            let vcId = vcs[indexPath.row].id
            let vc = try WalletAPI.shared.getCredentials(hWalletToken: hWalletToken, ids: [vcId])
            detialVC.setVcInfo(vc:vc.first)
            
            DispatchQueue.main.async {
                self.present(detialVC, animated: false, completion: nil)
            }
        }
    }
}

extension MainViewController: UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView,
                  layout collectionViewLayout: UICollectionViewLayout,
                  insetForSectionAt section: Int) -> UIEdgeInsets {

        return UIEdgeInsets(top: 10.0, left: 13.0, bottom: 10.0, right: 13.0)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let lay = collectionViewLayout as! UICollectionViewFlowLayout
//        let widthPerItem = collectionView.frame.width / 2 - lay.minimumInteritemSpacing
        let widthPerItem = collectionView.frame.width - lay.minimumInteritemSpacing
        
        return CGSize(width: widthPerItem - 20, height: 120)
    }
}
