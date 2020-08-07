//
//  ShareViewController.swift
//  MissCatShare
//
//  Created by Yuiga Wada on 2020/08/07.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import MobileCoreServices
import Social
import UIKit

class ShareViewController: SLComposeServiceViewController {
    // MARK: Items
    
    private lazy var mainColor = UIColor(hex: "2ba3bc")
    private var accountConfig = SLComposeSheetConfigurationItem()!
    private var visibilityConfig = SLComposeSheetConfigurationItem()!
    
    // MARK: Models
    
    private let userModel: UserModel = .init()
    
    // MARK: LifeCycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupComponent()
        setupMenu()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(true)
        setupGradiantNav()
    }
    
    private func setupComponent() {
        title = nil
        
        navigationController?.navigationBar.barStyle = .default
        
        navigationController?.navigationBar.tintColor = .white
        navigationController?.navigationBar.barTintColor = .white
        navigationController?.navigationBar.backgroundColor = mainColor
        navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.white]
        
        let controller = navigationController!.viewControllers.first!
        let missCatImage = UIImageView(image: UIImage(named: "MissCat"))
        
        missCatImage.contentMode = .scaleAspectFit
        controller.navigationItem.rightBarButtonItem!.title = "投稿"
        controller.navigationItem.titleView = missCatImage
    }
    
    private func setupMenu() {
        guard let currentUser = userModel.getCurrentUser() else { errorMessage(); fatalError() }
        accountConfig.title = "アカウント"
        accountConfig.value = "\(currentUser.username)@\(currentUser.instance)"
        accountConfig.tapHandler = {}
        
        let currentVisibity = userModel.getCurrentVisibility() ?? Visibility.public
        visibilityConfig.title = "公開範囲"
        visibilityConfig.value = currentVisibity.rawValue
        visibilityConfig.tapHandler = {}
    }
    
    // MARK: Overrides
    
    override func isContentValid() -> Bool {
        return contentText.count <= 1500
    }
    
    override func didSelectPost() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
            let itemProvider = extensionItem.attachments?.first else { return }
        
        let puclicURL = kUTTypeURL as String
        if itemProvider.hasItemConformingToTypeIdentifier(puclicURL) {
            itemProvider.loadItem(forTypeIdentifier: puclicURL, options: nil, completionHandler: { data, _ in
                guard let data = data else { self.errorMessage(); return }
                
                self.post(with: data)
                self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
            })
        }
    }
    
    override func configurationItems() -> [Any]! {
        // To add configuration options via table cells at the bottom of the sheet, return an array of SLComposeSheetConfigurationItem here.
        return [accountConfig, visibilityConfig]
    }
    
    // MARK: Design
    
    private func setupGradiantNav() {
        guard let navigationBar = navigationController?.navigationBar else { return }
        let gradientLayer: CAGradientLayer = CAGradientLayer()
        
        gradientLayer.colors = [UIColor(hex: "4691a3").cgColor,
                                UIColor(hex: "5AB0C5").cgColor,
                                UIColor(hex: "89d5e8").cgColor]
        gradientLayer.frame = navigationBar.layer.frame
        gradientLayer.startPoint = CGPoint(x: 0, y: 1)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0)
        
        let index = navigationBar.layer.sublayers?.count ?? 1
        navigationBar.layer.insertSublayer(gradientLayer, at: UInt32(index - 1))
    }
    
    // MARK: Others
    
    private func post(with data: NSSecureCoding) {
        guard let user = userModel.getCurrentUser(),
            let visibility = userModel.getCurrentVisibility() else { return }
        
        var text = contentText ?? ""
        let image = data as? UIImage
        
        if let url = data as? URL {
            text += " " + url.absoluteString
        }
        
        let model = PostModel(user: user)
        model.submitNote(text, image: image, visibility: visibility, completion: { success in
            if !success {
                self.errorMessage("送信に失敗しました")
            }
        })
    }
    
    private func errorMessage(_ message: String = "データの取得に失敗しました。") {
        let alert = UIAlertController(title: "エラー", message: message, preferredStyle: UIAlertController.Style.alert)
        present(alert, animated: true, completion: nil)
    }
}

extension UIColor {
    convenience init(hex: String, alpha: CGFloat) {
        let v = hex.map { String($0) } + Array(repeating: "0", count: max(6 - hex.count, 0))
        let r = CGFloat(Int(v[0] + v[1], radix: 16) ?? 0) / 255.0
        let g = CGFloat(Int(v[2] + v[3], radix: 16) ?? 0) / 255.0
        let b = CGFloat(Int(v[4] + v[5], radix: 16) ?? 0) / 255.0
        self.init(red: r, green: g, blue: b, alpha: min(max(alpha, 0), 1))
    }
    
    convenience init(hex: String) {
        self.init(hex: hex, alpha: 1.0)
    }
}
