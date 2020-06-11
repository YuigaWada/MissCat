//
//  AccountsDropdownMenu.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/06/10.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxCocoa
import RxSwift
import UIKit

class AccountsPopupMenu: AccountsMenu {
    @IBOutlet weak var containerView: UIView!
    @IBOutlet weak var selectLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setTheme()
        containerView.layer.cornerRadius = 8
        containerView.layer.borderWidth = 1
    }
    
    private func setTheme() {
        guard let theme = Theme.shared.currentModel else { return }
        
        let colorPattern = theme.colorPattern.ui
        let backgroundColor = theme.colorMode == .light ? colorPattern.base : colorPattern.sub3
        
        containerView.backgroundColor = backgroundColor
        containerView.layer.borderColor = UIColor.lightGray.cgColor
        
        selectLabel.textColor = colorPattern.text
    }
}

class AccountsDropdownMenu: AccountsMenu {
    override func viewDidLoad() {
        super.viewDidLoad()
        setupTableView()
    }
    
    // MARK: Setup
    
    func setupTableView() {
        let tableView = UITableView(frame: view.frame)
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        tableView.bounces = false
        tableView.showsVerticalScrollIndicator = false
        tableView.backgroundColor = .clear
        
        tableView.delegate = self
        tableView.dataSource = self
        
        view.addSubview(tableView)
    }
}

class AccountsMenu: UIViewController, UITableViewDelegate, UITableViewDataSource, Dropdown {
    var cellHeight: CGFloat = 50
    var selected: PublishRelay<Int> = .init()
    
    private var textColor: UIColor = .black
    private var iconColor: UIColor = .systemBlue
    
    var users: [SecureUser] = []
    
    // MARK: LifeCycle
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    convenience init(with users: [SecureUser], size: CGSize) {
        self.init()
        
        self.users = users
        cellHeight = size.height / CGFloat(users.count)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setTheme()
    }
    
    // MARK: Design
    
    private func setTheme() {
        guard let theme = Theme.shared.currentModel else { return }
        
        let mainColorHex = theme.mainColorHex
        let colorPattern = theme.colorPattern.ui
        let backgroundColor = theme.colorMode == .light ? colorPattern.base : colorPattern.sub3
        
        iconColor = UIColor(hex: mainColorHex)
        textColor = theme.colorPattern.ui.text
        view.backgroundColor = backgroundColor
        popoverPresentationController?.backgroundColor = backgroundColor
    }
    
    // MARK: Delegate
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return cellHeight
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selected.accept(indexPath.row)
        dismiss(animated: true, completion: nil)
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return users.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        
        cell.backgroundColor = .clear
        cell.textLabel?.textColor = textColor
        getUserInfo(user: users[indexPath.row]) { username, image in
            DispatchQueue.main.async {
                cell.textLabel?.text = username
                cell.imageView?.image = image
            }
        }
        
        return cell
    }
    
    private func getUserInfo(user: SecureUser, completion: @escaping (String, UIImage) -> Void) {
        guard let misskey = MisskeyKit(from: user) else { return }
        
        if let cache = Cache.shared.getUserInfo(user: user) { // キャッシュを活用する
            let fullUsername = "\(cache.username)@\(cache.host)"
            completion(fullUsername, round(to: cache.image))
            return
        }
        
        misskey.users.i { userInfo, _ in
            guard let userInfo = userInfo else { return }
            
            let username = userInfo.username ?? ""
            let fullUsername = "\(username)@\(user.instance)"
            _ = userInfo.avatarUrl?.toUIImage {
                guard let image = $0 else { return }
                
                let info = Cache.UserInfo(user: user,
                                          name: userInfo.name ?? username,
                                          username: username,
                                          host: user.instance,
                                          image: image)
                
                Cache.shared.saveUserInfo(info: info) // キャッシュしておく
                completion(fullUsername, self.round(to: image))
            }
        }
    }
    
    private func round(to image: UIImage) -> UIImage {
        let size = CGSize(width: 30, height: 30)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let ovalPath = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size))
            ovalPath.addClip()
            
            image.draw(in: CGRect(x: 0, y: 0, width: 30, height: 30))
        }
    }
}
