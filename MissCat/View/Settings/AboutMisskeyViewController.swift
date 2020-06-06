//
//  AboutMisskeyViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/12.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxSwift
import SafariServices
import UIKit

class AboutMisskeyViewController: UIViewController {
    @IBOutlet weak var backButton: UIButton!
    
    @IBOutlet weak var logoImageView: UIImageView!
    @IBOutlet weak var phraseLabel: UILabel!
    @IBOutlet weak var versionLabel: UILabel!
    @IBOutlet weak var developerLabel: UILabel!
    
    @IBOutlet weak var twitterIconImageView: UIImageView!
    @IBOutlet weak var misskeyAccountImageView: UIImageView!
    
    @IBOutlet weak var twitterAccountLabel: UIButton!
    @IBOutlet weak var misskeyAccountLabel: UIButton!
    
    @IBOutlet weak var twitterLogoLabel: UILabel!
    @IBOutlet weak var misskeyLogoImageView: UIImageView!
    
    @IBOutlet weak var twitterAccountContainer: UIView!
    @IBOutlet weak var MisskeyAccountContainer: UIView!
    
    private var disposeBag = DisposeBag()
    private lazy var components = [phraseLabel, versionLabel, developerLabel, twitterAccountContainer, MisskeyAccountContainer]
    
    private var initialAppearing: Bool = true
    
    var misskey: MisskeyKit?
    
    // MARK: LifeCycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setGradientLayer()
        setComponents()
        binding()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        
        if initialAppearing {
            hideComponents()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        guard initialAppearing else { super.viewDidAppear(animated); return }
        summon(after: false)
        super.viewDidAppear(animated)
        
        UIView.animate(withDuration: 0.7, delay: 0, options: .curveEaseInOut, animations: {
            self.summon(after: true)
        }, completion: nil)
        
        initialAppearing = false
    }
    
    private func binding() {
        backButton.rx.tap.subscribe(onNext: { _ in
            self.navigationController?.popViewController(animated: true)
        }).disposed(by: disposeBag)
        
        twitterAccountLabel.rx.tap.subscribe(onNext: { _ in
            self.openTwitterAccount()
        }).disposed(by: disposeBag)
        
        misskeyAccountLabel.rx.tap.subscribe(onNext: { _ in
            self.openMisskeyAccount()
        }).disposed(by: disposeBag)
        
        twitterAccountContainer.setTapGesture(disposeBag) {
            self.openTwitterAccount()
        }
        
        MisskeyAccountContainer.setTapGesture(disposeBag) {
            self.openMisskeyAccount()
        }
    }
    
    private func openTwitterAccount() {
        if let twitterScheme = URL(string: "twitter://user?screen_name=yuigawada"), UIApplication.shared.canOpenURL(twitterScheme) {
            UIApplication.shared.open(twitterScheme, options: [:], completionHandler: nil)
            return
        }
        
        guard let url = URL(string: "https://twitter.com/yuigawada"), UIApplication.shared.canOpenURL(url) else { return }
        DispatchQueue.main.async { self.openUrl(url) }
    }
    
    private func openMisskeyAccount() {
        guard let url = URL(string: "https://misskey.io/@wada"), UIApplication.shared.canOpenURL(url) else { return }
        DispatchQueue.main.async { self.openUrl(url) }
    }
    
    private func openUrl(_ url: URL) {
        present(SFSafariViewController(url: url), animated: true, completion: nil)
    }
    
    // MARK: Design
    
    private func setGradientLayer() {
        let gradientLayer: CAGradientLayer = CAGradientLayer()
        
        gradientLayer.colors = [UIColor(hex: "4691a3").cgColor,
                                UIColor(hex: "5AB0C5").cgColor,
                                UIColor(hex: "89d5e8").cgColor]
        gradientLayer.frame = view.bounds
        gradientLayer.startPoint = CGPoint(x: 0, y: 1)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0)
        
        view.layer.insertSublayer(gradientLayer, at: 0)
    }
    
    private func setComponents() {
        // Back Button
        backButton.titleLabel?.font = UIFont.awesomeSolid(fontSize: 15.0)
        
        // App Version
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        versionLabel.text = "v\(appVersion ?? "1.0")"
        
        // Logo
        twitterLogoLabel.font = UIFont.awesomeBrand(fontSize: 20)
        twitterLogoLabel.textColor = .systemBlue
        
        misskeyLogoImageView.image = UIImage(named: "misskey")
        misskeyLogoImageView.layer.cornerRadius = misskeyLogoImageView.frame.width / 4
        
        // Account Image
        setAccountImage()
    }
    
    private func setAccountImage() {
        // Twitter Icon
        twitterIconImageView.layer.cornerRadius = twitterIconImageView.frame.width / 2
        
        let twitterAccountIcon = "https://avatars.io/twitter/yuigawada"
        _ = twitterAccountIcon.toUIImage { image in
            guard let image = image else { return }
            DispatchQueue.main.async { self.twitterIconImageView.image = image }
        }
        
        // Misskey Icon
        misskeyAccountImageView.layer.cornerRadius = misskeyAccountImageView.frame.width / 2
        
        misskey?.users.showUser(username: "wada", host: "misskey.io") { user, error in
            guard let user = user, let avatarUrl = user.avatarUrl, error == nil else { return }
            
            _ = avatarUrl.toUIImage { image in
                guard let image = image else { return }
                DispatchQueue.main.async { self.misskeyAccountImageView.image = image }
            }
        }
    }
    
    private func hideComponents() {
        components.forEach { $0?.alpha = 0 }
    }
    
    /// Label, Buttton, Image等をすべて上からフェードインさせる処理
    /// - Parameter after: フェードイン前かフェードイン後か
    private func summon(after: Bool = false) {
        let sign = after ? 1 : -1
        components.forEach {
            guard let comp = $0 else { return }
            comp.alpha = after ? 1 : 0
            let originalFrame = comp.frame
            
            comp.frame = CGRect(x: originalFrame.origin.x,
                                y: originalFrame.origin.y + CGFloat(30 * sign),
                                width: originalFrame.width,
                                height: originalFrame.height)
        }
    }
}
