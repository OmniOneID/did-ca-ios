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
    
import Foundation
import DIDWalletSDK

struct ErrorHandler
{
    static func handle(_ error: Error) -> (title : String, message : String)
    {
        let title : String
        let message : String
        
        switch error {
        case let error as WalletSDKError:
            title   = error.code
            message = error.message
        case let error as WalletCoreError:
            title   = error.code
            message = error.message
        case let error as CommunicationSDKError:
            title   = error.code
            message = error.message
        default:
            title   = "error"
            message = "\((error))"
        }
        
        return (title, message)
    }
}
