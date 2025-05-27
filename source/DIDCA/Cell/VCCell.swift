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

import Foundation
import UIKit
import DIDWalletSDK

class VCCell: UICollectionViewCell {
    
    @IBOutlet weak var img: UIImageView!
    @IBOutlet weak var content1: UILabel!
    @IBOutlet weak var content2: UILabel!
    @IBOutlet weak var content3: UILabel!
    @IBOutlet weak var zkpStateLabel: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
    }
    
    /// Draw a list of saved vc
    /// - Parameter data: data
    public func drowVcInfo(data: Data, type: Int, isZkpIncluded : Bool) async throws {
        let vc = try! VerifiableCredential.init(from: data)
//        print("vc.credentialSchema.id: \(vc.credentialSchema.id)")
        
        let schemaData = try await CommnunicationClient.doGet(url: URL(string: vc.credentialSchema.id)!)
        let schema = try VCSchema.init(from: schemaData)
        
//        print("title: \(schema.title)")
//        print("schema: \(schema)")
//        print("schema.id: \(schema.id)")
//        print("vc.validUntil: \(vc.validUntil)")
//        print("vc.issuanceDate: \(vc.issuanceDate)")
                
        // hard coding (Need to change later)
        if schema.title.contains("Driver") {
            self.img.image = UIImage(named: "mid-card")
        } else {
            self.img.image = UIImage(named: "id-card")
        }
        self.img.contentMode = .scaleAspectFit
        self.content1.text = schema.title
        self.content2.text = "ValidUntil: "+SDKUtils.convertDateFormat(dateString: vc.validUntil)!
        self.content3.text = "IssuanceDate: "+SDKUtils.convertDateFormat(dateString: vc.issuanceDate)!
        self.zkpStateLabel.isHidden = !isZkpIncluded
    }
    
    /// Remove prefix from base64 string
    /// - Parameter base64String: base64String for img
    /// - Returns: image
    private func generateImg(base64String: String) throws -> UIImage {
        let base64StringWithoutPrefix = base64String.replacingOccurrences(of: "data:image/png;base64,", with: "")
        if let imageData = Data(base64Encoded: base64StringWithoutPrefix, options: .ignoreUnknownCharacters) {
            // Convert the Data object to a UIImage object
            if let image = UIImage(data: imageData) {
                return image
            }
        }
        throw NSError(domain: "generateImg error", code: 1)
    }
}
