//
//  AuthViewController.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/07.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit
import SafariServices

public protocol AuthViewControllerDelegate {
    func resultApiKey(_ apiKey: String?)
}

public class AuthViewController: UIViewController, SFSafariViewControllerDelegate  {
    
    private var callback: ((String?)->())?
    
    public var delegate: AuthViewControllerDelegate? // You can choose whether to use callback pattern or delegate pattern.
    
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        self.modalTransitionStyle = .crossDissolve
        
        guard let appSecret = MisskeyKit.auth.appSecret else { return }
        self.openAuthPage(appSecret)
    }
    
    public func resultApiKey(_ completion: @escaping (String?)->()) {
        self.callback = completion
    }
    
    private func openAuthPage(_ appSecret: String) {
        
        MisskeyKit.auth.startSession(appSecret: appSecret) { auth, error in
            guard let auth = auth, error == nil else { return }
            
            guard let url = URL(string: auth.token!.url) else { /* Error */ return }
            DispatchQueue.main.async {
                let vc = SFSafariViewController(url: url)
                
                vc.delegate = self
                self.present(vc, animated: true, completion: nil)
            }
            
        }
    }
    
    
    
    public func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        
        self.dismiss(animated: true, completion: nil)
        DispatchQueue.main.async {
            MisskeyKit.auth.getAccessToken() { auth, error in
                guard let _ = auth else { return }
                
                if let callback = self.callback {
                    callback(MisskeyKit.auth.getAPIKey())
                    return
                }
                else if let delegate = self.delegate {
                    delegate.resultApiKey(MisskeyKit.auth.getAPIKey())
                    return
                }
                
                fatalError("YOU MUST SET DELEGATE OR CALLBACK.")
            }
        }
    }
}
