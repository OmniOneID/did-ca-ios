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



class AddVCCell: UICollectionViewCell {
    
    @IBOutlet weak var img: UIImageView!
    @IBOutlet weak var content1: UILabel!
    @IBOutlet weak var content2: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
    }
    
    /// Draw a list of saved vc
    /// - Parameter data: data
    public func drowVcPlanInfo(data: Data) async throws {
        let vcplan = try! VCPlan.init(from: data)
        self.content1.text = vcplan.name // (name)
        self.content2.text = vcplan.description
        
        if vcplan.name.contains("Driver") {
            self.img.image = UIImage(named: "mid-card")
        } else {
            self.img.image = UIImage(named: "id-card")
        }
        self.img.contentMode = .scaleAspectFit
    }
}
