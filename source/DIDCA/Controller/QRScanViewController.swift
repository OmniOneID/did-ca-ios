/*
 * Copyright 2024 OmniOne.
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

import UIKit
import AVFoundation

protocol ScanQRViewControllerDelegate {
    func extractStringfromQRCode(qrString:String)
}

class QRScanViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    var delegate: ScanQRViewControllerDelegate!
    
    @IBOutlet weak var viewPreview: UIView!
    
    var isScanning: Bool = false
    var captureSession: AVCaptureSession!
    var videoPreviewLater: AVCaptureVideoPreviewLayer!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        isScanning = false
        captureSession = nil
    }
    
    override func viewDidAppear(_ animated: Bool) {
        
        self.startScanning()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        
        if isScanning {
            self.stopScanning()
        }
    }
    
    private func startScanning() -> Void {
        
        guard let captureDevice = AVCaptureDevice.default(for: .video) else { return }
        
        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: captureDevice)
        } catch {
            return
        }
        
        isScanning = true
        
        captureSession = AVCaptureSession()
        if (captureSession.canAddInput(videoInput)) {
            captureSession.addInput(videoInput)
        } else {
            return
        }
        
        let captureMetadataOutput = AVCaptureMetadataOutput()
        
        if (captureSession.canAddOutput(captureMetadataOutput)) {
            captureSession.addOutput(captureMetadataOutput)
            
            captureMetadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            captureMetadataOutput.metadataObjectTypes = [.qr]
        } else {

            return
        }
        
        videoPreviewLater = AVCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLater?.videoGravity = .resizeAspectFill
        videoPreviewLater?.frame = viewPreview.layer.bounds
        viewPreview.layer.addSublayer(videoPreviewLater)
        
        captureSession.startRunning()
        
    }
    
    @objc private func stopScanning() -> Void {
        
        isScanning = false
        
        captureSession?.stopRunning()
        
        captureSession = nil
        
        videoPreviewLater?.removeFromSuperlayer()
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
//            guard let stringValue = readableObject.stringValue else { return }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            if readableObject.type == AVMetadataObject.ObjectType.qr {
                weak var weakSelf: QRScanViewController!
                weakSelf = self;
                DispatchQueue.main.async(execute: {
                    weakSelf.processQRCode(metadataObj: readableObject)
                })
            }
        }

    }
    
    internal func processQRCode(metadataObj: AVMetadataMachineReadableCodeObject!) {
        
        if isScanning {
            
            if metadataObj.stringValue != nil {
                
                captureSession?.stopRunning()
                isScanning = false
                
                self.performSelector(onMainThread: #selector(stopScanning), with: nil, waitUntilDone: false)
                
                self.dismiss(animated: true) {
                    print("qr origin: \(metadataObj.stringValue ?? "")")
                    self.delegate.extractStringfromQRCode(qrString: metadataObj.stringValue ?? "")
                }
            }
        }
    }
    
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}

