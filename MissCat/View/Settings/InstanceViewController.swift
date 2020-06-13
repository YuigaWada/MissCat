//
//  InstanceViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/06/12.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Eureka
import RxCocoa
import RxSwift
import UIKit

class InstanceViewController: FormViewController {
    private var disposeBag: DisposeBag = .init()
    
    // MARK: LifeCycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupComponent()
        setTable()
        setTheme()
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
    
    private func getCellTextColor() -> UIColor {
        guard let theme = Theme.shared.currentModel else { return .black }
        return theme.colorPattern.ui.text
    }
    
    private func changeSeparatorStyle() {
        let currentColorMode = Theme.shared.currentModel?.colorMode ?? .light
        tableView.separatorStyle = currentColorMode == .light ? .singleLine : .none
    }
    
    // MARK: Setup
    
    private func setupComponent() {
        title = "お気に入りの絵文字"
        changeSeparatorStyle()
    }
    
    private func setTable() {
        guard let theme = Theme.shared.currentModel else { return }
        
        let licenseSection = getSection(with: theme)
        form +++ licenseSection
    }
    
    private func getSection(with theme: Theme.Model) -> Section {
        let section = Section(header: "Instance", footer: "絵文字情報はインスタンスごとに管理されます")
        
        // インスタンス情報を抽出
        var instances: [String: SecureUser] = [:]
        Cache.UserDefaults.shared.getUsers().forEach { user in
            guard !instances.keys.contains(user.instance) else { return }
            instances[user.instance] = user
        }
        
        // セクションを構築
        for (instance, user) in instances {
            section <<< LabelRow {
                $0.title = instance
            }.cellSetup { cell, _ in
                cell.height = { 60 }
            }.cellUpdate { cell, _ in
                cell.backgroundColor = self.getCellBackgroundColor()
                cell.textLabel?.textColor = self.getCellTextColor()
                cell.detailTextLabel?.textColor = self.getCellTextColor()
                
                cell.textLabel?.font = .boldSystemFont(ofSize: 17)
                cell.detailTextLabel?.font = .boldSystemFont(ofSize: 17)
            }.onCellSelection { _, _ in
                self.showReactionSettings(user: user)
            }
        }
        
        return section
    }
    
    // MARK: ViewController
    
    private func showReactionSettings(user: SecureUser) {
        guard let viewController = getViewController(name: "reaction-settings") as? ReactionSettingsViewController else { return }
        viewController.setOwner(user)
        navigationController?.pushViewController(viewController, animated: true)
    }
    
    private func getViewController(name: String) -> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyboard.instantiateViewController(withIdentifier: name)
        
        return viewController
    }
}
