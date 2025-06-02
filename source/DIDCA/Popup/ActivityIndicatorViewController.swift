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

class ActivityIndicatorViewController: UIViewController {

    public var presentClosure: (() async throws -> Void)?
    public var completeClosure: (() -> Void)?
    public var failureClosure: ((_ title:String, _ message:String) -> Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()

    }
    
    override func viewDidAppear(_ animated: Bool)
    {
        super.viewDidAppear(animated)
        
        Task { @MainActor in
            do
            {
                try await presentClosure?()
                self.dismiss(animated: false,
                             completion: completeClosure)
            }
            catch
            {
                let (title, message) = ErrorHandler.handle(error)
                
                self.dismiss(animated: false) {
                    guard let failailureClosure = self.failureClosure else { return }
                    failailureClosure(title, message)
                }
            }
        }
    }
}
