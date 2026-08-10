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
import Observation

struct ActionSheetContent : Identifiable
{
    let id : UUID = UUID()
    var icon : ImageResource
    var title : String
    var action : () -> Void
}

@Observable
class ActionSheetViewModel
{
    var title : String
    var message : String
    
    var contents: [ActionSheetContent]
    
    init(title: String, message: String, contents: [ActionSheetContent]) {
        self.title = title
        self.message = message
        self.contents = contents
    }
}
