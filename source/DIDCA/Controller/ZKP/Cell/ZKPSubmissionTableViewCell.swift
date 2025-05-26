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

protocol EyeSelectionDelegate {
    func didSelectEye(isSelected: Bool, index : Int)
}

class ZKPSubmissionTableViewCell: UITableViewCell {

    @IBOutlet weak var refNameLabel: UILabel!
    
    @IBOutlet weak var valueLabel: UILabel!
    
    @IBOutlet weak var eyeBtn: UIButton!

    public var delegate : EyeSelectionDelegate?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
    
    @IBAction func changeStatus(_ sender: UIButton) {
        sender.isSelected.toggle()
        
        guard let delegate = self.delegate else { return }
        
        delegate.didSelectEye(isSelected: sender.isSelected, index: self.tag)
    }
    

}
