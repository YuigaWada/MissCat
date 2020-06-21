//
//  TabSettingsCell.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/22.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Eureka
import RxCocoa
import RxSwift
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
        
        return .init(name: name,
                     kind: tabKind ?? .home,
                     userId: owner?.userId,
                     listId: nil)
    }
    
    var showMenuTrigger: PublishRelay<Void> = .init()
    var beingRemoved: Bool = false // removeすることになったらsetする
    
    private var tabSelected: Bool {
        return tabKind != nil
    }
    
    public override func setup() {
        super.setup()
        setTheme()
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        if !tabSelected, !beingRemoved {
            showMenuTrigger.accept(())
        }
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
        case .social:
            nameLabel.text = "ソーシャル"
            textFiled.placeholder = "Social"
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
