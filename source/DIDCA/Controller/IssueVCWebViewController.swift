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
import DIDWalletSDK

class IssueVCWebViewController: UIViewController {

    weak var delegate: DismissDelegate?
    private let hostUrlString = URLs.DEMO_URL + "/addVcInfo?did="
    public var vcSchemaId : String!
    
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
        contentController.add(self, name: "onCompletedAddVcUpload")
        contentController.add(self, name: "onFailedAddVcUpload")
        
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
        
        do {
            let holderDidDoc = try WalletAPI.shared.getDidDocument(type: DidDocumentType.HolderDidDocumnet)
            
            let serviceUrl = URL(string:"\(hostUrlString)\(holderDidDoc.id)&userName=\(Properties.getUserName()!)&vcSchemaId=\(vcSchemaId!)")
            print("servierUrl: \(serviceUrl!)")
            urlRequest = URLRequest(url: serviceUrl!)
            // progress 바 구현시 사용
            webView.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
        } catch {
            print("error \(error.localizedDescription)")
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        
        super.viewWillAppear(animated)
        loadWebView()
    }
    
    private func loadWebView() -> Void {
        
        activityIndicator.startAnimating()
        webView.load(urlRequest)
    }
    
    private func issueVC() {
        self.delegate?.didDidmissWithData()
        self.dismiss(animated: false)
    }
}

extension IssueVCWebViewController : WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    
    // progress 바 구현시 사용
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        
//        print("observeValue keyPath: \(String(describing: keyPath))")
//        print("wkWebView.estimatedProgress == \(Float((self.webView!.estimatedProgress)))")
    }
    
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        
        print("runJavaScriptAlertPanelWithMessage message: \(message)")
        completionHandler()
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

        print("userContentController callback \(message.name)")
        
        if message.name == "onCompletedAddVcUpload" {
            print(message.body)
            issueVC()
        } else if( message.name == "onFailedAddVcUpload"){
            
        } else {
            
        }
    }
}
