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

struct Toast: Identifiable, Equatable {
    let id: UUID = UUID()
    let message: String
//    let type: ToastType
    let duration: TimeInterval
    
//    enum ToastType {
//        case info
//        case success
//        case error
//        case warning
//        
//        var color: Color {
//            switch self {
//            case .info:     return Color.toastBlue
//            case .success:  return Color.toastGreen
//            case .error:    return Color.toastRed
//            case .warning:  return Color.toastOrange
//            }
//        }
//        
//        var bgColor: Color {
//            switch self {
//            case .info:     return Color.toastBlueBG
//            case .success:  return Color.toastGreenBG
//            case .error:    return Color.toastRedBG
//            case .warning:  return Color.toastOrangeBG
//            }
//        }
//        
//        var iconName: ImageResource {
//            switch self {
//            case .info: return .toastInfo
//            case .success: return .toastSuccess
//            case .error: return .toastError
//            case .warning: return .toastWarning
//            }
//        }
//    }
}

struct ToastView: View {
    let toast: Toast
//    let onDismiss: () -> Void
    
    var body: some View {
        Text(LocalizedStringResource(stringLiteral: toast.message))
            .font(
                .pretendard(
                    size: 14,
                    weight: .regular
                )
            )
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(content: {
                Capsule()
                    .foregroundStyle(.black)
            })
        .padding(.horizontal)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

#Preview {
    ToastView(toast: .init(message: "Hello world", duration: .infinity))
}
