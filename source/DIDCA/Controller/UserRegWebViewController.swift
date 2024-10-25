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

import Foundation
import WebKit
import UIKit
import DIDUtilitySDK
import DIDCoreSDK
import DIDWalletSDK
import DIDCommunicationSDK
import DIDDataModelSDK


class UserRegWebViewController: UIViewController {

    private let hostUrlString = URLs.DEMO_URL+"/addUserInfo"
    
    private var webView: WKWebView!
    
    @IBOutlet weak var subView: UIView!
    
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    
    private var urlRequest: URLRequest!
    
    @IBAction func backBtnAction(_ sender: Any) {
        DispatchQueue.main.async {
            self.dismiss(animated: false, completion: nil)
        }
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        // WebView web -> ios reg callback
        let contentController = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.preferences = WKPreferences()
        
        if #available(iOS 14.0, *) {
           config.defaultWebpagePreferences.allowsContentJavaScript = true
        } else {
           config.preferences.javaScriptEnabled = true
        }
        
        // web -> register native callback listener
        config.userContentController = contentController
        contentController.add(self, name: "onCompletedUserInfoUpload")
        contentController.add(self, name: "onFailedUserInfoUpload")
        
        // WebView init and load
        webView = WKWebView(frame: .zero, configuration: config)
        self.subView.addSubview(webView)
        
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.leadingAnchor.constraint(equalTo: self.subView.leadingAnchor).isActive = true
        webView.trailingAnchor.constraint(equalTo: self.subView.trailingAnchor).isActive = true
        webView.topAnchor.constraint(equalTo: self.subView.topAnchor).isActive = true
        webView.bottomAnchor.constraint(equalTo: self.subView.bottomAnchor).isActive = true
        self.webView.endEditing(false)
        // 유저가 방문한 페이지 조회
        self.subView.sendSubviewToBack(webView)
        // 자바 스크립트의 alert 액션 처리
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.allowsLinkPreview = false
        
        let serviceUrl = URL(string: hostUrlString)
        urlRequest = URLRequest(url: serviceUrl!)
        
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadWebView()
    }
    
    private func loadWebView() -> Void {
        activityIndicator.startAnimating()
        webView.load(urlRequest)
    }
    
    private func presentSubmitViewController() {
        let submitVC = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "MainViewController") as! MainViewController
        submitVC.modalPresentationStyle = .fullScreen
        DispatchQueue.main.async {
            self.present(submitVC, animated: false, completion: nil)
        }
    }
    
    private func userRegAction() {
        let popupVC = UIStoryboard.init(name: "Popup", bundle: nil).instantiateViewController(withIdentifier: "TwoButtonDialogViewController") as! TwoButtonDialogViewController
        popupVC.modalPresentationStyle = .overCurrentContext
        popupVC.setContentsMessage(message: "Would you like to set the Wallet for lock type?")
        popupVC.confirmButtonCompleteClosure = { [self] in
            Task {
                do {
                    // Personalization + Wallet Lock Setting Token Seed Request
                    let hWalletToken = try await SDKUtils.createWalletToken(purpose: WalletTokenPurposeEnum.PERSONALIZE_AND_CONFIGLOCK, userId: Properties.getUserId()!)
                    let result = try WalletAPI.shared.bindUser(hWalletToken: hWalletToken)
                    if result {
                        self.showPin(hWalletToken: hWalletToken)
                    } else {
                        print("개인화 실패")
                    }
                    
                } catch let error as WalletSDKError {
                    print("error code: \(error.code), message: \(error.message)")
                    PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
                } catch let error as WalletCoreError {
                    print("error code: \(error.code), message: \(error.message)")
                    PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
                } catch let error as CommunicationSDKError {
                    print("error code: \(error.code), message: \(error.message)")
                    PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
                } catch {
                    print("error :\(error)")
                }
            }
        }
        // NO
        popupVC.cancelButtonCompleteClosure = { [self] in
            Task {
                do {
                    // personalized
                    let hWalletToken = try await SDKUtils.createWalletToken(purpose: WalletTokenPurposeEnum.PERSONALIZED, userId: Properties.getUserId()!)
                    
                    let result = try WalletAPI.shared.bindUser(hWalletToken: hWalletToken)
                    if result {
                        nextView()
                    } else {
                        print("fail to personalized")
                    }
                } catch let error as WalletSDKError {
                    print("error code: \(error.code), message: \(error.message)")
                    PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
                } catch let error as WalletCoreError {
                    print("error code: \(error.code), message: \(error.message)")
                    PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
                } catch let error as CommunicationSDKError {
                    print("error code: \(error.code), message: \(error.message)")
                    PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
                } catch {
                    print("error :\(error)")
                }
            }
        }
        self.present(popupVC, animated: false, completion: nil)
    }
    
    func nextView() {
        let stepVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "StepViewController") as! StepViewController
        stepVC.setStepType(stepType: StepTypeEnum.STEP_TYPE_2)
        stepVC.modalPresentationStyle = .fullScreen
        DispatchQueue.main.async {
            self.present(stepVC, animated: false, completion: nil)
        }
    }

    func showPin(hWalletToken: String) {
        // PIN view
        let pinVC = UIStoryboard.init(name: "PIN", bundle: nil).instantiateViewController(withIdentifier: "PincodeViewController") as! PincodeViewController
        pinVC.modalPresentationStyle = .fullScreen
        pinVC.setRequestType(type: PinCodeTypeEnum.PIN_CODE_REGISTRATION_LOCK_TYPE)
        pinVC.confirmButtonCompleteClosure = { [self] passcode in
            do {
                print("hWalletToken: \(hWalletToken)")
                print("passcode: \(passcode)")
                _ = try WalletAPI.shared.registerLock(hWalletToken: hWalletToken, passcode: passcode, isLock: true)
                nextView()
            } catch let error as WalletSDKError {
                print("error code: \(error.code), message: \(error.message)")
                PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
            } catch let error as WalletCoreError {
                print("error code: \(error.code), message: \(error.message)")
                PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
            } catch let error as CommunicationSDKError {
                print("error code: \(error.code), message: \(error.message)")
                PopupUtils.showAlertPopup(title: error.code, content: error.message, VC: self)
            } catch {
                print("error :\(error)")
            }
        }
        pinVC.cancelButtonCompleteClosure = {
            PopupUtils.showAlertPopup(title: "Notification", content: "canceled by user", VC: self)
        }
        DispatchQueue.main.async {
            self.present(pinVC, animated: false, completion: nil)
        }
    }
}

extension UserRegWebViewController : WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    }
    
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        
        print("runJavaScriptAlertPanelWithMessage message: \(message)")
        completionHandler()
        PopupUtils.showDialogPopup(title: "alert", content: message, VC: self)
    }
        
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        
        print("webview didFinish")
        
        activityIndicator.stopAnimating()
    }
    
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        
        print("webview didCommit")
    }
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        
//        print("webview didStartProvisionalNavigation")
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        
        activityIndicator.stopAnimating()
        print("webview didFail")
    }
    
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!){
        
        print("webview redirect")
    }
    
    // Call url loading request (navigation)
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void){
        
        print("webview callback")
        
        // http, http, html or no navigation
        if let url = navigationAction.request.url, url.scheme != "http" && url.scheme != "https", !url.absoluteString.hasSuffix("html") {
            
            print("url: \(String(describing: navigationAction.request.url))")
            print("url.scheme: \(String(describing: url.scheme))")
            
            decisionHandler(.cancel)
        }
        // Allow URL navigation only when the protocol is http or https
        else {
            print("allow request")
            decisionHandler(.allow)
        }
    }
    
    func webViewDidClose(_ webView: WKWebView) {
        
        webView.removeFromSuperview()
    }
    
    // web -> native callback listener
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {

        print("userContentController callback func: \(message.name)")
        print("userContentController callback param: \(message.body)")
        
        if message.name == "onCompletedUserInfoUpload" {
            let jsonStr = ((message.body) as! String)
            if let jsonData = jsonStr.data(using: .utf8) {
                do {
                    // JSON 파싱
                    let user = try JSONDecoder().decode(User.self, from: jsonData)
                    print("UserID: \(user.userId)")
                    print("Username: \(user.username)")
                    
                    Properties.setUserId(id: user.userId)
                    Properties.setUserName(name: user.username)
                    
                    userRegAction()
                } catch {
                    print("Error parsing JSON: \(error)")
                }
            }
        }
    }
}
