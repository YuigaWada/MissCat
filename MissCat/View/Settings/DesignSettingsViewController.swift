//
//  DesignSettingsViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/22.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Eureka
import UIKit

class DesignSettingsViewController: FormViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        setupComponent()
        setTable()
    }
    
    private func setupComponent() {
        title = "デザイン"
        tableView.backgroundColor = .white
    }
    
    private func setTable() {
        guard let theme = Theme.shared.currentModel else { return }
        
        let tabSettingsSection = getTabSettingsSection(with: theme)
        let themeSettingsSection = getThemeSettingsSection(with: theme)
        
        form +++ tabSettingsSection +++ themeSettingsSection
    }
    
    private func getTabSettingsSection(with theme: Theme.Model) -> MultivaluedSection {
        var section = MultivaluedSection(multivaluedOptions: [.Reorder, .Insert, .Delete],
                                         header: "上タブ設定",
                                         footer: "タップで表示名を変更することができます") {
            $0.tag = "textfields"
            $0.addButtonProvider = { _ in
                ButtonRow {
                    $0.title = "タブを追加"
                }.cellUpdate { cell, _ in
                    cell.textLabel?.textAlignment = .left
                }
            }
            
            $0.multivaluedRowToInsertAt = { _ in
                TabSettingsRow()
            }
        }
        
        theme.tab.reversed().forEach { tab in
            let row = TabSettingsRow {
                $0.tabKind = tab.kind
                $0.currentName = tab.name
            }
            section.insert(row, at: 0)
        }
        
        return section
    }
    
    private func getThemeSettingsSection(with theme: Theme.Model) -> Section {
        let currentColor = UIColor(hex: theme.mainColorHex)
        return Section("テーマ設定")
            <<< SegmentedRow<String>() { $0.options = ["Light", "Dark"]; $0.value = theme.colorMode == .light ? "Light" : "Dark" }
            <<< ColorPickerRow { $0.currentColor = currentColor }
    }
}
