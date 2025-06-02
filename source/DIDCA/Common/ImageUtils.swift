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

struct ImageUtils
{
    /// Generate the image by base64 string
    /// - Parameter base64String: base64String for img
    /// - Returns: image
    public static func generateImg(base64String: String) throws -> UIImage {
        
        // Remove the prefix from the Base64 string
        let base64StringWithoutPrefix = base64String.replacingOccurrences(of: "data:image/png;base64,", with: "")
        if let imageData = Data(base64Encoded: base64StringWithoutPrefix, options: .ignoreUnknownCharacters) {
            // Convert a Data object to a UIImage object
            if let image = UIImage(data: imageData) {
                return image
            }
        }
        throw NSError(domain: "generateImg error", code: 1)
    }
    
    static func resizeImg(_ img: UIImage, to size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        img.draw(in: CGRect(origin: .zero, size: size))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage ?? img
    }
    
    static func generateImg(base64String: String, targetSize: CGSize) throws -> UIImage
    {
        let img = try generateImg(base64String: base64String)
        return resizeImg(img, to: targetSize)
    }
}
