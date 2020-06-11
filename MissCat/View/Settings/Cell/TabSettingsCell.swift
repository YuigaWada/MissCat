//
//  TabSettingsCell.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/22.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Eureka
import UIKit

public class TabSettingsCell: Cell<Theme.Tab>, CellType {
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var textFiled: UITextField!
    
    var tabKind: Theme.TabKind?
    var owner: SecureUser?
    var value: Theme.Tab {
        var name = textFiled.text ?? ""
        if name.isEmpty {
            name = textFiled.placeholder ?? ""
        }
        
        if tabKind == .home {
            name = "@\(owner?.username ?? "")"
        }
        
        return .init(name: name,
                     kind: tabKind ?? .home,
                     userId: owner?.userId,
                     listId: nil)
    }
    
    private var tabSelected: Bool {
        return tabKind != nil
    }
    
    public override func setup() {
        super.setup()
        setTheme()
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        showAlert()
    }
    
    // MARK: Design
    
    private func setTheme() {
        guard let theme = Theme.shared.currentModel else { return }
        let colorPattern = theme.colorPattern.ui
        
        nameLabel.textColor = colorPattern.text
        textFiled.textColor = colorPattern.text
        
        let backView = UIView()
        backView.backgroundColor = .clear
        selectedBackgroundView = backView
    }
    
    // MARK: Menu
    
    private func showAccountsMenu(_ kind: Theme.TabKind) {
        guard let parent = parentViewController,
            let popup = getViewController(name: "accounts-popup") as? AccountsPopupMenu else { return }
        
        let users = Cache.UserDefaults.shared.getUsers()
        let size = CGSize(width: parent.view.frame.width * 3 / 5, height: 50 * CGFloat(users.count))
        popup.cellHeight = size.height / CGFloat(users.count)
        popup.users = users
        
        popup
            .selected.map { users[$0] } // 選択されたユーザーを返す
            .subscribe(onNext: { user in
                self.owner = user
                self.setKind(kind)
            })
        
        popup.modalPresentationStyle = .overCurrentContext
        parentViewController?.present(popup, animated: true, completion: {
            popup.view.backgroundColor = popup.view.backgroundColor?.withAlphaComponent(0.7)
        })
    }
    
    private func getViewController(name: String) -> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyboard.instantiateViewController(withIdentifier: name)
        
        return viewController
    }
    
    private func showAlert() {
        guard !tabSelected else { return }
        let alert = UIAlertController(title: "タブ", message: "追加するタブの種類を選択してください", preferredStyle: .alert)
        
        addMenu(to: alert, title: "ホーム", kind: .home)
        addMenu(to: alert, title: "ローカル", kind: .local)
        addMenu(to: alert, title: "グローバル", kind: .global)
        
        // 以下２つは別のアップデートで実装する
//        addMenu(to: alert, title: "ユーザー", kind: .user)
//        addMenu(to: alert, title: "リスト", kind: .list)
        
        parentViewController?.present(alert, animated: true)
    }
    
    private func addMenu(to alert: UIAlertController, title: String, kind: Theme.TabKind) {
        alert.addAction(UIAlertAction(title: title, style: .default, handler: { _ in
            self.showAccountsMenu(kind)
        }))
    }
    
    // MARK: Utiliteis
    
    func setKind(_ kind: Theme.TabKind) {
        tabKind = kind
        switch kind {
        case .home:
            nameLabel.text = "ホーム"
            textFiled.placeholder = "@\(owner?.username ?? "")"
        case .local:
            nameLabel.text = "ローカル"
            textFiled.placeholder = "Local"
        case .global:
            nameLabel.text = "グローバル"
            textFiled.placeholder = "Global"
        case .user:
            nameLabel.text = "ユーザー"
            textFiled.placeholder = "User"
        case .list:
            nameLabel.text = "リスト"
            textFiled.placeholder = "List"
        }
    }
    
    func setName(_ name: String) {
        textFiled.text = name
    }
    
    func setOwner(userId: String?) {
        guard let userId = userId else { return }
        owner = Cache.UserDefaults.shared.getUser(userId: userId)
    }
}

public final class TabSettingsRow: Row<TabSettingsCell>, RowType {
    public var tab: Theme.Tab {
        return cell.value
    }
    
    public required init(tag: String?) {
        super.init(tag: tag)
        cellProvider = CellProvider<TabSettingsCell>(nibName: "TabSettingsCell")
    }
}
