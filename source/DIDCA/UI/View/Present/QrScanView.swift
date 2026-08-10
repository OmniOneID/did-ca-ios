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

/// QR 스캔 모달. 카메라 프리뷰 위에 dim + 정사각형 가이드를 얹는다.
/// 첫 QR 인식 시 onScanned(payload), 좌상단 X 또는 권한 거부 시 onClose.
///
/// 시뮬레이터엔 카메라가 없어, 사진 라이브러리의 QR 이미지를 PhotosPicker 로 골라
/// 디코딩하는 경로로 대체한다 (`#if targetEnvironment(simulator)` — 기기 빌드엔 미포함).
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

            // dim · cutout · ScanFrame · 안내문구를 한 wrapper ZStack 의 sibling
            // 으로 두고 wrapper 자체에 .ignoresSafeArea() 적용. 모든 자식이
            // 같은 screen-center 에 정렬됨 — .overlay 로 둘러싸면 overlay 콘텐츠
            // 가 SafeArea 안쪽 좌표로 평가되어 ScanFrame 이 safe-area-center 로
            // 내려가면서 cutout 과 어긋났음. blendMode 가 ScanFrame 까지 번지지
            // 않게 dim/ cutout 만 inner ZStack + compositingGroup 으로 격리.
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
        // 시뮬레이터 — 사진 라이브러리의 QR 이미지를 골라 디코딩.
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
    /// 선택한 사진에서 QR 페이로드를 디코딩해 onScanned 로 전달.
    private func decodePicked(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let payload = Self.decodeQR(from: image)
        else { return }
        onScanned(payload)
    }

    /// CIDetector 로 이미지에서 첫 QR 코드 문자열을 추출.
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
    /// 카메라 권한 확인 — 미결정이면 요청, 거부면 QR-E-01 안내를 띄운다.
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

    /// 권한 거부 시 — QR 스캔 화면을 유지한 채 QR-E-01 안내 다이얼로그를 띄운다.
    /// 화면 이탈은 사용자가 좌상단 X 로 직접 (설계 QR-E-01 결과화면: "QR scan · 권한 안내").
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
