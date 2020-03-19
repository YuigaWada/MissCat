//
//  AuthWebViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/08.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxCocoa
import RxSwift
import UIKit
import WebKit

public class AuthWebViewController: UIViewController, WKUIDelegate, WKNavigationDelegate {
    @IBOutlet weak var returnButton: UIButton!
    @IBOutlet weak var webView: WKWebView!
    
    public var completion: PublishRelay<String> = .init()
    
    private var currentUrl: URL?
    private var currentType: AuthType = .Signup
    private var appSecret: String?
    private var misskeyInstance: String?
    
    private let disposeBag = DisposeBag()
    
    // MARK: LifeCycle
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        setupReturnButton()
        
        removeWebKitCache()
        if let url = currentUrl {
            loadPage(url: url)
        }
    }
    
    private func setupWebView() {
        webView.uiDelegate = self
        webView.navigationDelegate = self
        
        webView.configuration.websiteDataStore = WKWebsiteDataStore.default() // LocalStorageを許可
    }
    
    private func setupReturnButton() {
        returnButton.rx.tap.subscribe(onNext: {
            self.dismiss(animated: true, completion: nil)
        }).disposed(by: disposeBag)
    }
    
    private func removeWebKitCache() {
        URLSession.shared.reset {} // cookieやキャッシュのリセット
        
        let dataStore = WKWebsiteDataStore.default() // WKWebsiteに保存されている全ての情報の削除
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records, completionHandler: {})
        }
        
        WKProcessPool.shared.reset()
    }
    
    // MARK: Publics
    
    public func setupSignup(misskeyInstance: String, appSecret: String) {
        self.appSecret = appSecret
        self.misskeyInstance = misskeyInstance
        currentType = .Signup
        
        let httpsUrl = URL(string: "https://" + misskeyInstance)
        let httpUrl = URL(string: "http://" + misskeyInstance)
        
        let validHttpsUrl = (httpsUrl != nil ? UIApplication.shared.canOpenURL(httpsUrl!) : false)
        let validHttpUrl = (httpUrl != nil ? UIApplication.shared.canOpenURL(httpUrl!) : false)
        
        guard validHttpsUrl || validHttpUrl else { return }
        
        currentUrl = validHttpsUrl ? httpsUrl! : httpUrl!
        if webView != nil, let url = currentUrl {
            loadPage(url: url)
        }
    }
    
    public func setupLogin(misskeyInstance: String, appSecret: String) {
        self.appSecret = appSecret
        self.misskeyInstance = misskeyInstance
        currentType = .Login
        
        MisskeyKit.changeInstance(instance: misskeyInstance) // インスタンスを変更
        MisskeyKit.auth.startSession(appSecret: appSecret) { auth, error in
            guard let auth = auth,
                let token = auth.token,
                error == nil,
                let url = URL(string: token.url) else { /* Error */ return }
            
            self.currentUrl = url
            if self.webView != nil {
                self.loadPage(url: url)
            }
        }
    }
    
    // MARK: Privates
    
    private func loadPage(url: URL) {
        DispatchQueue.main.async {
            self.webView.load(URLRequest(url: url))
            self.currentUrl = nil
        }
    }
    
    /// LocalStorageからログイン処理が完了したかどうかを確認する
    /// - Parameter handler: success→true
    private func checkLogined(handler: @escaping (Bool) -> Void) {
        // 新規登録やログインが完了したらLocalStorageに["i":(key)]が格納されるので、ここからログイン処理が完了したかどうかを確認する
        webView.evaluateJavaScript("localStorage.getItem(\"i\")") { result, _ in
            guard let result = result as? String, result != "" else { handler(false); return }
            handler(true)
        }
    }
    
    /// ApiKeyを取得し、StartViewControllerへと流す(comletion→StartViewController)
    private func getApiKey() {
        MisskeyKit.auth.getAccessToken { auth, _ in
            guard auth != nil, let apiKey = MisskeyKit.auth.getAPIKey() else { return }
            
            DispatchQueue.main.async {
                self.dismiss(animated: true, completion: nil)
                self.completion.accept(apiKey)
            }
        }
    }
    
    // MARK: Delegate
    
    // WebViewの読み込みが完了したらログイン処理が完了したかどうかをチェックする
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { // 読み込み完了
        guard let appSecret = self.appSecret, let misskeyInstance = self.misskeyInstance else { return }
        
        checkLogined { success in
            guard success else { return }
            if self.currentType == .Signup {
                self.setupLogin(misskeyInstance: misskeyInstance, appSecret: appSecret) // WebKit内でログインページへと遷移させる
            } else { // If currentType == .Login
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { // TODO: コールバックに対応させる
                    self.getApiKey()
                }
            }
        }
    }
}

extension AuthWebViewController {
    public enum AuthType {
        case Signup
        case Login
    }
}

extension WKProcessPool {
    static var shared = WKProcessPool()
    
    func reset() {
        WKProcessPool.shared = WKProcessPool()
    }
}
