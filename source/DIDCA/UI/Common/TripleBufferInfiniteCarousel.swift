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

struct TripleBufferInfiniteCarousel<Item: Identifiable, Page: View>: View {
    let items: [Item]
    let interval: TimeInterval
    let initialDelay: Duration
    let animationDuration: TimeInterval
    let isUserInteractionEnabled: Bool
    let page: (Item) -> Page

    @Environment(\.scenePhase) private var scenePhase

    @State private var currentIndex: Int = 0
    @State private var offsetX: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    @State private var isAutoEnabled: Bool = true
    @State private var loopToken = UUID()
    @State private var isAnimating = false

    init(
        items: [Item],
        interval: TimeInterval = 3.0,
        initialDelay: Duration = .milliseconds(250),
        animationDuration: TimeInterval = 0.35,
        isUserInteractionEnabled: Bool = false,
        @ViewBuilder page: @escaping (Item) -> Page
    ) {
        self.items = items
        self.interval = interval
        self.initialDelay = initialDelay
        self.animationDuration = animationDuration
        self.isUserInteractionEnabled = isUserInteractionEnabled
        self.page = page
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width

            ZStack {
                if items.isEmpty {
                    EmptyView()
                } else if items.count == 1 {
                    page(items[0])
                        .frame(width: w)
                } else {
          
                    HStack(spacing: 0) {
                        page(prevItem).frame(width: w)
                        page(currentItem).frame(width: w)
                        page(nextItem).frame(width: w)
                    }
                    .offset(x: offsetX)
                    .clipped()
                    .contentShape(Rectangle())
                    .allowsHitTesting(isUserInteractionEnabled)
                    .onAppear {
                        containerWidth = w
                        offsetX = -w
                        isAutoEnabled = true
                        restartLoop()
                    }
                    .onChange(of: geo.size.width) { _, newW in
                        containerWidth = newW
                        withoutAnimation {
                            offsetX = -newW
                        }
                    }
                    .onChange(of: scenePhase) { _, phase in
                        
                        if case .active = phase
                        {
                            isAutoEnabled = true
                            restartLoop()
                        }
                        else
                        {
                            isAutoEnabled = false
                            stopLoop()
                        }
                    }
                    .task(id: loopToken) {
                        await autoLoop()
                    }
                }
            }
        }
    }

    // MARK: - Items (wrap-around)

    private var prevIndex: Int { (currentIndex - 1 + items.count) % items.count }
    private var nextIndex: Int { (currentIndex + 1) % items.count }

    private var prevItem: Item { items[prevIndex] }
    private var currentItem: Item { items[currentIndex] }
    private var nextItem: Item { items[nextIndex] }

    // MARK: - Auto loop (no Combine, leak-safe)

    private func restartLoop() { loopToken = UUID() }
    private func stopLoop() { loopToken = UUID() }

    private func autoLoop() async {
        guard items.count > 1 else { return }

        try? await Task.sleep(for: initialDelay)
        if Task.isCancelled { return }

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(interval))
            if Task.isCancelled { return }

            guard isAutoEnabled else { continue }
            await MainActor.run {
                moveNext()
            }
        }
    }

    // MARK: - Animation

    @MainActor
    private func moveNext() {
        guard !isAnimating, items.count > 1, containerWidth > 0 else { return }
        isAnimating = true

        let w = containerWidth

        withAnimation(.easeInOut(duration: animationDuration)) {
            offsetX = -2 * w
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(animationDuration * 1_000_000_000))

            currentIndex = nextIndex
            withoutAnimation {
                offsetX = -w
            }
            isAnimating = false
        }
    }

    private func withoutAnimation(_ updates: () -> Void) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { updates() }
    }
}

#Preview {
    let items = [
        Banner(name: "a"),
        Banner(name: "b")
    ]
    
    TripleBufferInfiniteCarousel(
        items: items,
        interval: 2.5,
        initialDelay: .milliseconds(300),
        animationDuration: 0.35,
        isUserInteractionEnabled: false
    ) { item in
        ZStack {
            RoundedRectangle(cornerRadius: 24)
            Text(item.name)
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
//                .frame(height: 220)
    }
}
