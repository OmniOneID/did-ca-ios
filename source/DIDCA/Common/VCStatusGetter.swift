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

struct VCStatusGetter
{
    struct VCMetaVO : Jsonable
    {
        let vcId : String
        let vcMeta : String
    }
    
    static func getStatus(vcId : String) async throws -> VCStatusEnum
    {
        let urlString = "\(URLs.API_URL)/api-gateway/api/v1/vc-meta?vcId=\(vcId)"
        
        let vo : VCMetaVO = try await CommunicationClient.sendRequest(urlString: urlString,
                                                                      httpMethod: .GET)
        
        let vcMeta : VCMeta = try .init(from: try MultibaseUtils.decode(encoded: vo.vcMeta))
        return vcMeta.status
    }
    
    static func getStatus(vcIds : [String]) async throws -> [String : VCStatusEnum]
    {
        var status : [String : VCStatusEnum] = [:]
        
        for vcId in vcIds
        {
            status[vcId] = try await getStatus(vcId: vcId)
        }
        
        return status
    }
}
