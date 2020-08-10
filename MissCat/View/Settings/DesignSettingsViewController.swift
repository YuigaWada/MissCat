//
//  DesignSettingsViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/22.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Eureka
import RxSwift
import UIKit

class DesignSettingsViewController: FormViewController {
    var homeViewController: HomeViewController?
    private var disposeBag: DisposeBag = .init()
    private var tabSettingsSection: Section?
    
    // MARK: LifeCycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupComponent()
        setTable()
        bindTheme()
        setTheme()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        let model = saveSettings()
        updateNavBarColor(with: model)
    }
    
    // MARK: Design
    
    private func bindTheme() {
        let theme = Theme.shared.theme
        
        theme.map { $0.colorPattern.ui }.subscribe(onNext: { colorPattern in
            self.view.backgroundColor = colorPattern.base
        }).disposed(by: disposeBag)
    }
    
    private func setTheme() {
        if let colorPattern = Theme.shared.currentModel?.colorPattern.ui {
            view.backgroundColor = colorPattern.base
            tableView.backgroundColor = colorPattern.base
        }
    }
    
    /// ステータスバーの文字色
    override var preferredStatusBarStyle: UIStatusBarStyle {
        let currentColorMode = Theme.shared.currentModel?.colorMode ?? .light
        return currentColorMode == .light ? UIStatusBarStyle.default : UIStatusBarStyle.lightContent
    }
    
    private func getCellBackgroundColor() -> UIColor {
        guard let theme = Theme.shared.currentModel else { return .white }
        return theme.colorMode == .light ? theme.colorPattern.ui.base : theme.colorPattern.ui.sub2
    }
    
    private func changeSeparatorStyle() {
        let currentColorMode = Theme.shared.currentModel?.colorMode ?? .light
        tableView.separatorStyle = currentColorMode == .light ? .singleLine : .none
    }
    
    // MARK: Setup
    
    private func setupComponent() {
        title = "デザイン"
        changeSeparatorStyle()
    }
    
    private func setTable() {
        guard let theme = Theme.shared.currentModel else { return }
        
        let tabSettingsSection = getTabSettingsSection(with: theme)
        let themeSettingsSection = getThemeSettingsSection(with: theme)
        
        form +++ tabSettingsSection +++ themeSettingsSection
        
        self.tabSettingsSection = tabSettingsSection
    }
    
    private func getTabSettingsSection(with theme: Theme.Model) -> MultivaluedSection {
        var section = MultivaluedSection(multivaluedOptions: [.Reorder, .Insert, .Delete],
                                         header: "上タブ設定",
                                         footer: "タップで表示名を変更することができます") {
            $0.tag = "tab-settings"
            $0.addButtonProvider = { _ in
                ButtonRow {
                    $0.title = "タブを追加"
                    $0.baseCell.backgroundColor = self.getCellBackgroundColor()
                }.cellUpdate { cell, _ in
                    cell.textLabel?.textAlignment = .left
                }
            }
            
            $0.multivaluedRowToInsertAt = { _ in
                TabSettingsRow {
                    guard let cell = $0.cell else { return }
                    
                    $0.baseCell.backgroundColor = self.getCellBackgroundColor()
                    $0.cell?.showMenuTrigger.subscribe(onNext: {
                        self.showAlert(for: cell)
                    }).disposed(by: self.disposeBag)
                }
            }
        }
        
        // 保存されたテーマ情報からタブを再構築
        theme.tab.reversed().forEach { tab in
            var tabName = tab.name
            
            // ホームタブがデフォルトなら@usernameに変更しておく(デフォルト値は___Home___)
            if tab.kind == .home, tab.name == "___Home___", let userId = tab.userId {
                if let user = Cache.UserDefaults.shared.getUser(userId: userId) {
                    tabName = "@\(user.username)"
                }
            }
            
            let row = TabSettingsRow {
                $0.cell?.setName(tabName)
                $0.cell?.setKind(tab.kind)
                $0.cell?.setOwner(userId: tab.userId)
                $0.baseCell.backgroundColor = self.getCellBackgroundColor()
            }
            section.insert(row, at: 0)
        }
        
        return section
    }
    
    private func getThemeSettingsSection(with theme: Theme.Model) -> Section {
        let currentColor = UIColor(hex: theme.mainColorHex)
        return Section("テーマ設定")
            <<< SegmentedRow<String>() {
                $0.tag = "color-mode"
                $0.options = ["Light", "Dark"]
                $0.value = theme.colorMode == .light ? "Light" : "Dark"
                $0.baseCell.backgroundColor = self.getCellBackgroundColor()
            }
            <<< ColorPickerRow {
                $0.tag = "main-color"
                $0.cell.setColor(currentColor)
                $0.baseCell.backgroundColor = self.getCellBackgroundColor()
            }
    }
    
    // MARK: Menu
    
    private func showAlert(for cell: TabSettingsCell) {
        let alert = UIAlertController(title: "タブ", message: "追加するタブの種類を選択してください", preferredStyle: .alert)
        
        addMenu(to: alert, cell: cell, title: "ホーム", kind: .home)
        addMenu(to: alert, cell: cell, title: "ローカル", kind: .local)
        addMenu(to: alert, cell: cell, title: "ソーシャル", kind: .social)
        addMenu(to: alert, cell: cell, title: "グローバル", kind: .global)
        
        alert.addAction(UIAlertAction(title: "閉じる", style: .default, handler: { _ in
            guard let section = self.tabSettingsSection else { return }
            cell.beingRemoved = true
            section.remove(at: section.count - 2) // 追加しようとしていたセルをけしてあげる
            alert.dismiss(animated: true, completion: nil)
        }))
        
        present(alert, animated: true)
    }
    
    private func addMenu(to alert: UIAlertController, cell: TabSettingsCell, title: String, kind: Theme.TabKind) {
        alert.addAction(UIAlertAction(title: title, style: .default, handler: { _ in
            self.showAccountsMenu(for: cell, kind: kind)
        }))
    }
    
    private func showAccountsMenu(for cell: TabSettingsCell, kind: Theme.TabKind) {
        guard let popup = getViewController(name: "accounts-popup") as? AccountsPopupMenu else { return }
        
        let users = Cache.UserDefaults.shared.getUsers()
        let size = CGSize(width: view.frame.width * 3 / 5, height: 50 * CGFloat(users.count))
        popup.cellHeight = size.height / CGFloat(users.count)
        popup.users = users
        
        popup.selected.map { users[$0] } // 選択されたユーザーを返す
            .subscribe(onNext: { user in
                cell.owner = user
                cell.setKind(kind)
            }).disposed(by: disposeBag)
        
        popup.modalPresentationStyle = .overCurrentContext
        present(popup, animated: true, completion: {
            popup.view.backgroundColor = popup.view.backgroundColor?.withAlphaComponent(0.7)
        })
    }
    
    private func getViewController(name: String) -> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyboard.instantiateViewController(withIdentifier: name)
        
        return viewController
    }
    
    // MARK: Update / Save
    
    private func saveSettings() -> Theme.Model {
        let tab = getTabSettings()
        let mainColorHex = getMainColorSettings()
        let colorMode = getColorModeSettings()
        
        var needAllRelaunch: Bool = false
        let newModel = Theme.Model(tab: tab, mainColorHex: mainColorHex, colorMode: colorMode)
        if let currentModel = Theme.shared.currentModel {
            needAllRelaunch = Theme.needAllRelaunch(between: currentModel, and: newModel)
        }
        
        Theme.shared.save(with: newModel)
        
        if needAllRelaunch {
            homeViewController?.relaunchView(start: .main)
        }
        
        return newModel
    }
    
    private func updateNavBarColor(with newModel: Theme.Model) {
        UINavigationBar.changeColor(back: newModel.colorPattern.ui.base, text: newModel.colorPattern.ui.text) // ナビゲーションバーの色を変更
    }
    
    private func getTabSettings() -> [Theme.Tab] {
        guard let tabSection = form.sectionBy(tag: "tab-settings") as? MultivaluedSection else { return [] }
        
        var tabs: [Theme.Tab] = []
        tabSection.allRows.forEach { // なぜかcompactMapできない...
            guard let row = $0 as? TabSettingsRow else { return }
            tabs.append(row.tab)
        }
        
        if tabs.count == 0 { // タブが0個の場合はデフォルトのtab情報を返す
            guard let defaultModel = Theme.Model.getDefault(), defaultModel.tab.count > 0 else { fatalError() }
            return defaultModel.tab
        }
        
        return tabs
    }
    
    private func getColorModeSettings() -> Theme.ColerMode {
        guard let colorModeRow = form.rowBy(tag: "color-mode") as? SegmentedRow<String>,
            let colorMode = colorModeRow.value else { return .light }
        
        return colorMode == "Light" ? .light : .dark
    }
    
    private func getMainColorSettings() -> String {
        guard let colorRow = form.rowBy(tag: "main-color") as? ColorPickerRow else { return "2F7CF6" }
        return colorRow.currentColorHex
    }
}

extension UINavigationBar {
    static func changeColor(back backgroundColor: UIColor, text textColor: UIColor) {
        let appearance = UINavigationBar.appearance()
        appearance.barTintColor = backgroundColor
        appearance.titleTextAttributes = [NSAttributedString.Key.foregroundColor: textColor]
    }
}
