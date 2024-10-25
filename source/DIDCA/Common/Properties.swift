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

#if swift(>=5.8)
@_documentation(visibility: private)
#endif
public class Properties {
    /// set PushToken
    /// - Parameter token: push token
    public static func setPushToken(token: String) {
        UserDefaults.standard.setValue(token, forKey: "push_token")
        UserDefaults.standard.synchronize()
    }

    /// get getPushToken
    /// - Returns: push token
    public static func getPushToken() -> String? {
        let result: String? = UserDefaults.standard.string(forKey: "push_token")
        return result
    }
    
    /// set UserName
    /// - Parameter id: userName
    public static func setUserName(name: String) {
        UserDefaults.standard.setValue(name, forKey: "user_name")
        UserDefaults.standard.synchronize()
    }
    
    /// get UserName
    /// - Returns: userName
    public static func getUserName() -> String? {
        let result: String? = UserDefaults.standard.string(forKey: "user_name")
        return result
    }
    
    /// get UserId
    /// - Returns: userId
    public static func getUserId() -> String? {
        let result: String? = UserDefaults.standard.string(forKey: "user_id")
        return result
    }
    
    /// set UserId
    /// - Parameter id: userId
    public static func setUserId(id: String) {
        UserDefaults.standard.setValue(id, forKey: "user_id")
        UserDefaults.standard.synchronize()
    }
    
    
    /// <#Description#>
    /// - Returns: didDoc
    public static func getRegDidDocCompleted() -> Bool? {
        let result: Bool? = UserDefaults.standard.bool(forKey: "reg_diddoc_completed")
        return result
    }
    
    /// <#Description#>
    /// - Parameter status: status
    public static func setRegDidDocCompleted(status: Bool?) {
        UserDefaults.standard.setValue(status, forKey: "reg_diddoc_completed")
        UserDefaults.standard.synchronize()
    }
    
    /// <#Description#>
    /// - Returns: <#description#>
    public static func getSubmitCompleted() -> Bool? {
        let result: Bool? = UserDefaults.standard.bool(forKey: "submit_completed")
        return result
    }
    
    /// <#Description#>
    /// - Parameter status: <#status description#>
    /// - Returns: <#description#>
    public static func setSubmitCompleted(status: Bool?) -> Void {
        UserDefaults.standard.setValue(status, forKey: "submit_completed")
        UserDefaults.standard.synchronize()
    }
    
    /// <#Description#>
    /// - Returns: <#description#>
    public static func getTasUrl() -> String? {
        let result: String? = UserDefaults.standard.string(forKey: "tas_url")
        return result
    }
    
    /// <#Description#>
    /// - Parameter status: <#status description#>
    /// - Returns: <#description#>
    public static func setTasUrl(status: String?) -> Void {
        UserDefaults.standard.setValue(status, forKey: "tas_url")
        UserDefaults.standard.synchronize()
    }
    
    /// <#Description#>
    /// - Returns: <#description#>
    public static func getVerifierUrl() -> String? {
        let result: String? = UserDefaults.standard.string(forKey: "verifier_url")
        return result
    }
    
    /// <#Description#>
    /// - Parameter status: <#status description#>
    /// - Returns: <#description#>
    public static func setVerifierUrl(status: String?) -> Void {
        UserDefaults.standard.setValue(status, forKey: "verifier_url")
        UserDefaults.standard.synchronize()
    }
    
    /// <#Description#>
    /// - Returns: <#description#>
    public static func getCaAppId() -> String? {
        
        let result: String? = UserDefaults.standard.string(forKey: "caAppId")
        return result
    }
    
    /// <#Description#>
    /// - Returns: <#description#>
    public static func generateCaAppId() -> Void {
        
        if getCaAppId() != nil { return }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMM"
        let prefix = formatter.string(from: Date())
        
        let characters = "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        var randomString = ""
        
        for _ in 0..<11 {
            let index = Int.random(in: 0..<characters.count)
            let randomChar = characters[characters.index(characters.startIndex, offsetBy: index)]
            randomString.append(randomChar)
        }
        
        let caAppId = prefix + randomString
        print("caAppId: \(caAppId)")
        
        UserDefaults.standard.setValue(caAppId, forKey: "caAppId")
        UserDefaults.standard.synchronize()
    }
    
}
