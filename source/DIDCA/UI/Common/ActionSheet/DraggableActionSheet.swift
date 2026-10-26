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
    // Slide-down length of the sheet dismiss. Referenced from outside (e.g. timing of presenting a follow-up modal).
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
                        // Remove animation for offset changes while dragging
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

            // Design spec BottomSheet — 4 between title and description, 12 below the description. Selection rows paint their
            // background to the row edge, so without this spacing the first row (current value) looks stuck to the description.
            VStack(alignment: .leading, spacing: 4) {
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
            .padding(.bottom, 12)

            ForEach(viewModel.contents.indices, id: \.self) { index in
                
                let content = viewModel.contents[index]
                Button {
                    dismiss()
                    content.action()
                } label: {
                    if let selected = content.selected {
                        // Selection row (design spec BottomSheet select) — no icon; the label starts at the same x (24) as the title,
                        // and on the right only the current value gets a check (20). Other rows keep alignment with a blank of the same width.
                        HStack(spacing: 16) {
                            Text(content.title)
                                .font(.pretendard(size: 16, weight: .medium))
                                .foregroundStyle(.black)
                            Spacer()
                            Image(.icCheckOrange)
                                .resizable()
                                .frame(width: 20, height: 20)
                                .opacity(selected ? 1 : 0)
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, 24)
                        .contentShape(Rectangle())
                        .background(selected ? Color.paleOrange : .clear)
                    } else {
                        HStack(spacing: 16) {
                            if let icon = content.icon {
                                Image(icon)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(.paleOrange)
                                    )
                            }
                            
                            Text(content.title)
                                .font(.pretendard(size: 16, weight: .medium))
                                .foregroundStyle(.black)
                            Spacer()
                            
                            Image(.icChevR)
                                .padding()
                        }
                        .padding()
                        // Make the whole row the tap area — otherwise, with a .plain button, the Spacer's empty space isn't tappable and
                        // only the icon, text and chevron respond.
                        .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                
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
