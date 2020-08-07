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
    
    // MARK: States
    
    private lazy var currentUser: SecureUser? = self.userModel.getCurrentUser()
    private var currentVisibility: Visibility = .public
    
    // MARK: Models
    
    private let userModel: UserModel = .init()
    
    // MARK: LifeCycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupComponent()
        setupMenu()
    }
    
    private func setupComponent() {
        title = nil
        
        navigationController?.navigationBar.barStyle = .default
        
        navigationController?.navigationBar.tintColor = .white
        navigationController?.navigationBar.barTintColor = .white
        navigationController?.navigationBar.backgroundColor = mainColor
        navigationController?.navigationBar.setBackgroundImage(UIImage(named: "back"), for: .default)
        
        let controller = navigationController!.viewControllers.first!
        let missCatImage = UIImageView(image: UIImage(named: "MissCat"))
        
        missCatImage.contentMode = .scaleAspectFit
        controller.navigationItem.rightBarButtonItem!.title = "投稿"
        controller.navigationItem.titleView = missCatImage
    }
    
    private func setupMenu() {
        guard let currentUser = currentUser else { errorMessage(); fatalError() }
        accountConfig.title = "アカウント"
        accountConfig.value = "\(currentUser.username)@\(currentUser.instance)"
        accountConfig.tapHandler = {
            self.showAccountsViewController()
        }
        
        let currentVisibity = userModel.getCurrentVisibility() ?? Visibility.public
        visibilityConfig.title = "公開範囲"
        visibilityConfig.value = currentVisibity.rawValue
        visibilityConfig.tapHandler = {
            self.showVisibilityViewController()
        }
    }
    
    // MARK: Overrides
    
    override func isContentValid() -> Bool {
        return contentText.count <= 1500
    }
    
    override func didSelectPost() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
            let itemProvider = extensionItem.attachments?.first else { return }
        
        let puclicURL = kUTTypeURL as String
        let typeImage = kUTTypeImage as String
        
        for typeIdentifier in [puclicURL, typeImage] {
            guard itemProvider.hasItemConformingToTypeIdentifier(typeIdentifier) else { continue }
            itemProvider.loadItem(forTypeIdentifier: typeIdentifier, options: nil, completionHandler: { data, _ in
                guard let data = data else { self.errorMessage(); return }
                
                self.post(with: data)
                self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
            })
        }
    }
    
    override func configurationItems() -> [Any]! {
        return [accountConfig, visibilityConfig]
    }
    
    // MARK: VC
    
    private func showAccountsViewController() {
        let users = userModel.getUsers()
        let accountsVC = AccountsViewController(with: users)
        accountsVC.delegate = self
        navigationController?.pushViewController(accountsVC, animated: true)
    }
    
    private func showVisibilityViewController() {
        let visibilityVC = VisibilityViewController()
        visibilityVC.delegate = self
        navigationController?.pushViewController(visibilityVC, animated: true)
    }
    
    // MARK: Others
    
    private func post(with data: NSSecureCoding) {
        guard let user = currentUser else { return }
        
        var text = contentText ?? ""
        var image: UIImage?
        
        if let url = data as? URL {
            if url.absoluteString.prefix(8) == "file:///", let imageData = try? Data(contentsOf: url) { // 画像ファイルの場合
                image = UIImage(data: imageData)
            } else { // 通常のURLの場合
                text += " " + url.absoluteString
            }
        }
        
        let model = PostModel(user: user)
        model.submitNote(text, image: image, visibility: currentVisibility, completion: { success in
            if !success { self.errorMessage("送信に失敗しました") }
        })
    }
    
    private func errorMessage(_ message: String = "データの取得に失敗しました。") {
        let alert = UIAlertController(title: "エラー", message: message, preferredStyle: UIAlertController.Style.alert)
        present(alert, animated: true, completion: nil)
    }
}

// MARK: Delegate

extension ShareViewController: AccountsProtocol {
    func switchAccount(userId: String) {
        guard let user = userModel.getUser(userId: userId) else { errorMessage(); fatalError() }
        currentUser = user
        accountConfig.value = "\(user.username)@\(user.instance)"
    }
}

extension ShareViewController: VisibilityProtocol {
    func switchVisibility(_ visibility: Visibility) {
        currentVisibility = visibility
        visibilityConfig.value = visibility.rawValue
    }
}

// MARK: UIColor

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
