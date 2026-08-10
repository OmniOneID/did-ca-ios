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

struct DotSpinner: View {
    private let dotCount = 8

    var radius: CGFloat = 22
    var dotSize: CGFloat = 11
    var stepDuration: Double = 0.12
    var inactiveScale: CGFloat = 0.9

    @State private var startDate = Date()

    var body: some View {
        TimelineView(.periodic(from: startDate, by: stepDuration)) { context in
            let diff = context.date.timeIntervalSince(startDate)
            let activeIndex = Int(diff / stepDuration) % dotCount
            
            ZStack {
                ForEach(0..<dotCount, id: \.self) { i in
                    let isActive = i == activeIndex
                    Circle()
                        .frame(width: dotSize, height: dotSize)
                        .foregroundStyle(isActive ? Color.customPrimary : Color.dotGray)
                        .scaleEffect(isActive ? 1.0 : inactiveScale)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(Double(i) * 45))
                        .animation(
                            .easeInOut(duration: min(0.10, stepDuration * 0.6)),
                            value: activeIndex
                        )
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        DotSpinner()
    }
    .padding()
}
