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
import AVFoundation
#if targetEnvironment(simulator)
import PhotosUI
import CoreImage
#endif

/// QR scan modal. Overlays a dim layer + square guide on the camera preview.
/// onScanned(payload) on the first QR recognized; onClose on the top-left X or permission denial.
///
/// The simulator has no camera, so instead a QR image is picked from the photo library via PhotosPicker
/// and decoded (`#if targetEnvironment(simulator)` — not included in device builds).
struct QrScanView: View {
    var onScanned: (String) -> Void = { _ in }
    var onClose: () -> Void = {}

    private let squareSide: CGFloat = 220

    #if targetEnvironment(simulator)
    @State private var pickedItem: PhotosPickerItem?
    #else
    @State private var showCamera = false
    #endif

    var body: some View {
        ZStack {
            scannerLayer

            // dim · cutout · ScanFrame · guide text are siblings in one wrapper ZStack,
            // with .ignoresSafeArea() applied to the wrapper itself. All children
            // align to the same screen center — wrapping with .overlay made the overlay content
            // evaluate in safe-area coordinates, so ScanFrame dropped to the safe-area center
            // and misaligned with the cutout. So blendMode doesn't bleed into ScanFrame,
            // only dim/cutout are isolated in an inner ZStack + compositingGroup.
            ZStack {
                ZStack {
                    Color.black.opacity(0.7)

                    RoundedRectangle(cornerRadius: 8)
                        .frame(width: squareSide, height: squareSide)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .allowsHitTesting(false)

                ScanFrame()
                    .frame(width: squareSide, height: squareSide)
                    .allowsHitTesting(false)

                Text("Please scan the QR code inside the square.")
                    .font(.pretendard(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.9))
                    .offset(y: squareSide / 2 + 20)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea()

            chrome
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.scanBackground.ignoresSafeArea())
        #if !targetEnvironment(simulator)
        .task { await resolveCameraPermission() }
        #endif
    }

    @ViewBuilder
    private var scannerLayer: some View {
        #if targetEnvironment(simulator)
        // Simulator — pick a QR image from the photo library and decode it.
        PhotosPicker(selection: $pickedItem, matching: .images) {
            VStack(spacing: 10) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 40))
                Text("Pick a QR image")
                    .font(.pretendard(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(width: squareSide, height: squareSide)
        }
        .onChange(of: pickedItem) { _, item in
            Task { await decodePicked(item) }
        }
        #else
        if showCamera {
            QRCodeScanner(onScan: onScanned)
                .ignoresSafeArea()
        }
        #endif
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(.icCloseWhite)
                        .padding()
                }
                .accessibilityIdentifier("closeButton")
            }
            .frame(height: 56)

            Text("QR Scan")
                .font(.pretendard(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 4)

            Spacer()
        }
    }

    #if targetEnvironment(simulator)
    /// Decodes the QR payload from the chosen photo and passes it to onScanned.
    private func decodePicked(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let payload = Self.decodeQR(from: image)
        else { return }
        onScanned(payload)
    }

    /// Extracts the first QR code string from the image with CIDetector.
    private static func decodeQR(from image: UIImage) -> String? {
        guard let ciImage = CIImage(image: image) else { return nil }
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        let features = detector?.features(in: ciImage) as? [CIQRCodeFeature] ?? []
        return features.compactMap(\.messageString).first
    }
    #else
    /// Camera permission check — request if undetermined; show the camera-permission notice if denied.
    private func resolveCameraPermission() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .video) {
                showCamera = true
            } else {
                showPermissionDeniedPopup()
            }
        default:
            showPermissionDeniedPopup()
        }
    }

    /// On permission denial — keep the QR scan screen and show the camera-permission notice dialog.
    /// The user leaves the screen themselves via the top-left X (the design spec's "QR scan · permission notice" screen).
    private func showPermissionDeniedPopup() {
        OverlayManager.shared.showPopup(
            title: "Camera permission required",
            message: "Camera permission is required to scan QR codes.",
            primaryButtonTitle: "Open Settings",
            primaryAction: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        )
    }
    #endif
}

private struct ScanFrame: View {
    var body: some View {
        ZStack {
            corner(rotation: 0,   alignment: .topLeading)
            corner(rotation: 90,  alignment: .topTrailing)
            corner(rotation: 270, alignment: .bottomLeading)
            corner(rotation: 180, alignment: .bottomTrailing)
        }
    }

    private func corner(rotation: Double, alignment: Alignment) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 44))
            path.addLine(to: CGPoint(x: 0, y: 6))
            path.addArc(
                center: CGPoint(x: 6, y: 6),
                radius: 6,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: 44, y: 0))
        }
        .stroke(.scanCorner, lineWidth: 2)
        .frame(width: 44, height: 44)
        .rotationEffect(.degrees(rotation))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

#Preview {
    QrScanView()
}
