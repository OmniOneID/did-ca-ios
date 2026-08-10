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



struct DraggableActionSheet: View {
    // 시트 dismiss 슬라이드다운 길이. 외부(예: 후속 모달 present 타이밍)에서 참조한다.
    static let dismissDuration: TimeInterval = 0.22

    @Binding var isPresented: Bool

    @State var viewModel : ActionSheetViewModel

    @State private var showSheet = false
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging : Bool = false


    var body: some View {
        ZStack(alignment: .bottom) {
            if isPresented {
                Color.black.opacity(showSheet ? 0.35 : 0)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismiss()
                    }

                sheetView
                    .offset(y: showSheet ? dragOffset : UIScreen.main.bounds.height)
                    .transaction { transaction in
                        // 드래그 중 offset 변화에는 애니메이션 제거
                        if isDragging
                        {
                            transaction.animation = nil
                        }
                    }
            }
        }
        .onChange(of: isPresented) { _, newValue in
            if newValue {
                dragOffset = 0

                withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                    showSheet = true
                }
            }
        }
    }

    private var sheetView: some View {
        VStack(spacing: 0) {
            dragHandle

            VStack(alignment: .leading) {
                Text(viewModel.title)
                    .font(.pretendard(size: 18, weight: .semibold))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.leading)
                    .frame(height: 25)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(viewModel.message)
                    .font(.pretendard(size: 13, weight: .regular))
                    .foregroundStyle(.customGray)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            
            ForEach(viewModel.contents.indices, id: \.self) { index in
                
                let content = viewModel.contents[index]
                Button {
                    dismiss()
                    content.action()
                } label: {
                    HStack(spacing: 16) {
                        
                        Image(content.icon)
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.paleOrange)
                            )
                        
                        Text(content.title)
                            .font(.pretendard(size: 16, weight: .medium))
                            .foregroundStyle(.black)
                        Spacer()
                        
                        Image(.icChevR)
                            .padding()
                    }
                    .padding()
                }
                
                if index < viewModel.contents.count - 1 {
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 16,
                topTrailingRadius: 16
            )
            .fill(.white)
            .ignoresSafeArea()
        )
    }

    private var dragHandle: some View {
        VStack {
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 44, height: 5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .contentShape(Rectangle())
        .gesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                isDragging = true
                let diff = value.location.y - value.startLocation.y
                dragOffset = max(diff, 0)
            }
            .onEnded { value in
                isDragging = false
                let diff = value.location.y - value.startLocation.y

                if diff > 120 {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: Self.dismissDuration)) {
            showSheet = false
            dragOffset = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dismissDuration) {
            isPresented = false
        }
    }
}

struct DraggableActionSheetContentView: View {
    @State private var showSheet = false

    var body: some View {
        ZStack {
            Button("액션시트 열기") {
                showSheet = true
            }
            
            DraggableActionSheet(
                isPresented: $showSheet,
                viewModel: .init(
                    title: "Add certificate",
                    message: "Add a certificate to your wallet by choosing from a list or scanning a QR code.",
                    contents: [
                        .init(icon: .icList,
                              title: "From list",
                              action: {
                                  ()
                              }),
                        .init(icon: .icQr,
                              title: "Scan QR",
                              action: {
                                  ()
                              })
                    ]
                )
            )
        }
    }
}

#Preview {
    DraggableActionSheetContentView()
}
