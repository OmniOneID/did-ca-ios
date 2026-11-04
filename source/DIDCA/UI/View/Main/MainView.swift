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

struct MainView: View {

    @Environment(AppCoordinator.self) private var coordinator

    @State private var isPresentedAdding: Bool = false
    @State private var isPresentedSubmitting: Bool = false

    private var isEmpty: Bool { coordinator.credentials.isEmpty }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header

                if isEmpty {
                    NoCertificateView(onAdd: { isPresentedAdding = true })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical) {
                        VStack(spacing: 12) {
                            ForEach(coordinator.credentials) { cred in
                                Button {
                                    coordinator.push(.vcDetail(cred))
                                } label: {
                                    CredentialCard(credential: cred)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 16)
                        .padding(.bottom, 20)
                    }

                    presentBar
                }
            }
            .background(.backgroundGray)

            DraggableActionSheet(
                isPresented: $isPresentedAdding,
                viewModel: .init(
                    title: "Add certificate",
                    message: "Add a certificate to your wallet by choosing from a list or scanning a QR code.",
                    contents: [
                        .init(icon: .icList,
                              title: "From list",
                              action: { coordinator.push(.protocolSelect) }),
                        .init(icon: .icQr,
                              title: "Scan QR",
                              action: { scanQR(intent: .issue) })
                    ]
                )
            )

            DraggableActionSheet(
                isPresented: $isPresentedSubmitting,
                viewModel: .init(
                    title: "Present",
                    message: "Present your issued certificate in person (proximity)\nor by scanning a QR code.",
                    contents: [
                        .init(icon: .icProximity,
                              title: "Proximity",
                              action: { coordinator.push(.proximity) }),
                        .init(icon: .icQr,
                              title: "Scan QR",
                              action: { scanQR(intent: .present) })
                    ]
                )
            )
        }
    }

    // "Scan QR" — after the action sheet goes down, show the QR scan modal and receive the result in main.
    // The scanner screen is shared by the + button / Present button, and the kind of QR received is restricted by
    // which one was tapped (`intent`) — for a different kind, the flow isn't started and only a notice is shown.
    private func scanQR(intent: ScanIntent) {
        Task {
            // Wait briefly so the modal comes up after the action sheet dismiss animation finishes.
            // The duration follows DraggableActionSheet's dismissDuration, plus a small margin so it doesn't coincide
            // with the same deadline as the sheet's isPresented=false handling.
            try? await Task.sleep(for: .seconds(DraggableActionSheet.dismissDuration) + .milliseconds(30))
            guard let payload = await coordinator.presentQrScan() else { return }
            await coordinator.handleScannedQR(payload, intent: intent)
        }
    }

    private var header: some View {
        HStack {
            Button { coordinator.push(.menu) } label: {
                Image(.icMenu).padding()
            }
            .accessibilityIdentifier("menuButton")

            Text("DID CA")
                .font(.pretendard(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            Button { isPresentedAdding = true } label: {
                Image(.icAddWhite).padding()
            }
            .accessibilityIdentifier("addButton")
        }
        .frame(height: 56)
        .background {
            Color.customPrimary.ignoresSafeArea(edges: .top)
        }
    }

    private var presentBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.borderGray)
                .frame(height: 1)

            Button { isPresentedSubmitting = true } label: {
                Text("Present")
                    .font(.pretendard(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(height: 52)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12).fill(.customPrimary)
                    )
                    .shadow(color: .customPrimary.opacity(0.3), radius: 3, x: 0, y: 2)
            }
            .accessibilityIdentifier("presentButton")
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background(.backgroundGray)
    }
}

private struct CredentialCard: View {
    let credential: Credential

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(credential.icon)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [.paleOrange, .borderOrange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(credential.issuer)
                        .font(.pretendard(size: 11, weight: .medium))
                        .tracking(0.2)
                        .foregroundStyle(.customGray)
                        .lineLimit(1)

                    Text(credential.name)
                        .font(.pretendard(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(.icChevR)
            }

            HStack(spacing: 6) {
                StatusBadge(status: credential.status)
                FormatBadge(kind: credential.badge)
                if credential.zkp {
                    FormatBadge(kind: .zkp)
                }
                Spacer()
            }
            .padding(.top, 12)

            DashLiner()
                .stroke(.borderGray, style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                .frame(height: 1)
                .padding(.top, 12)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ISSUED")
                        .font(.pretendard(size: 10, weight: .semibold))
                        .kerning(0.4)
                        .foregroundStyle(.customGray)
                    Text(credential.issued ?? "—")
                        .font(.pretendard(size: 12, weight: .semibold))
                        .foregroundStyle(.black)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("VALID UNTIL")
                        .font(.pretendard(size: 10, weight: .semibold))
                        .kerning(0.4)
                        .foregroundStyle(.customGray)
                    Text(credential.valid ?? "—")
                        .font(.pretendard(size: 12, weight: .semibold))
                        .foregroundStyle(.black)
                }
            }
            .padding(.top, 10)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.white)
                .shadow(color: .primaryShadow.opacity(0.08), radius: 6, x: 0, y: 4)
                .shadow(color: .black.opacity(0.03), radius: 1, x: 0, y: 1)
        )
    }
}

#Preview("Empty") {
    MainView()
        .environment(AppCoordinator())
}

#Preview("Populated") {
    let c = AppCoordinator()
    c.credentials = SampleCredentials.all
    return MainView().environment(c)
}
