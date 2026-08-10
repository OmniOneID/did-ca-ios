//
/*
 * Copyright 2026 OmniOne.
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
    
import SwiftUI

extension Font
{
    // VF named instance 의 PostScript name 으로 직접 룩업.
    // "PretendardVariable" (family base) 만으로는 매칭 실패 → 시스템 폰트로 fallback 됨.
    static func pretendard(
        size : CGFloat,
        weight : Weight
    ) -> Font
    {
        return .custom(
            pretendardPostScriptName(for: weight),
            size: size
        )
    }

    private static func pretendardPostScriptName(for weight: Weight) -> String {
        let suffix: String
        if weight == .ultraLight      { suffix = "Thin" }        // 100
        else if weight == .thin       { suffix = "ExtraLight" }  // 200
        else if weight == .light      { suffix = "Light" }       // 300
        else if weight == .medium     { suffix = "Medium" }      // 500
        else if weight == .semibold   { suffix = "SemiBold" }    // 600
        else if weight == .bold       { suffix = "Bold" }        // 700
        else if weight == .heavy      { suffix = "ExtraBold" }   // 800
        else if weight == .black      { suffix = "Black" }       // 900
        else                          { suffix = "Regular" }     // 400 / default
        return "PretendardVariable-\(suffix)"
    }
}
