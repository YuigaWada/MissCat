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
    var value: Theme.Tab {
        var name = textFiled.text ?? ""
        if name.isEmpty {
            name = textFiled.placeholder ?? ""
        }
        
        return .init(name: name,
                     kind: tabKind ?? .home,
                     userId: nil,
                     listId: nil)
    }
    
    private var tabSelected: Bool {
        return tabKind != nil
    }
    
    public override func setup() {
        super.setup()
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        showAlert()
    }
    
    private func showAlert() {
        guard !tabSelected else { return }
        let alert = UIAlertController(title: "タブ", message: "追加するタブの種類を選択してください", preferredStyle: .alert)
        
        addMenu(to: alert, title: "ホーム", kind: .home)
        addMenu(to: alert, title: "ローカル", kind: .local)
        addMenu(to: alert, title: "グローバル", kind: .global)
        addMenu(to: alert, title: "ユーザー", kind: .user)
        addMenu(to: alert, title: "リスト", kind: .list)
        
        parentViewController?.present(alert, animated: true)
    }
    
    private func addMenu(to alert: UIAlertController, title: String, kind: Theme.TabKind) {
        alert.addAction(UIAlertAction(title: title, style: .default, handler: { _ in
            self.setKind(kind)
        }))
    }
    
    func setKind(_ kind: Theme.TabKind) {
        tabKind = kind
        switch kind {
        case .home:
            nameLabel.text = "ホーム"
            textFiled.placeholder = "Home"
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
