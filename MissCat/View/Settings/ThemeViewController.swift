//
//  ThemeViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/16.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import UIKit

public class ThemeViewController: UITableViewController {
    private var sections = ["一般", "投稿", "リプライ", "Renote", "通知欄"]
    private lazy var tables: [Section: [Table]] = {
        var _tables = [Section: [Table]]()
        for i in 0 ... 4 { _tables[Section(rawValue: i)!] = [] }
        
        return _tables
    }()
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setTables()
        setTableView()
    }
    
    private func setTables() {
        //
        tables[.General] = [.init(title: "メインカラー", currentColor: .systemBlue),
                            .init(title: "背景色", currentColor: .white),
                            .init(title: "境界線", currentColor: .lightGray)]
        
        
        tables[.Post] = [.init(type: .Mock),
                         .init(title: "文字色", currentColor: .black),
                         .init(title: "リンク色", currentColor: .systemBlue),
                         .init(title: "リアクションセル", currentColor: .lightGray),
                         .init(title: "自分のリアクション", currentColor: .systemOrange),
                         .init(title: "文字サイズ", type: .Size)]
        
        tables[.Renote] = [.init(type: .Mock),
                           .init(title: "Renoteしたユーザー名", currentColor: .systemGreen),
                           .init(title: "引用RNのボーダー", currentColor: .systemBlue)]
        
        tables[.Reply] = [.init(type: .Mock),
                          .init(title: "背景", currentColor: .lightGray),
                          .init(title: "文字色", currentColor: .black)]
        
        tables[.Notifications] = [.init(type: .Mock),
                                  .init(title: "リアクション", currentColor: .systemRed),
                                  .init(title: "Renote", currentColor: .systemGreen),
                                  .init(title: "文字色", currentColor: .black)]
    }
    
    private func setTableView() {
        tableView.delegate = self
        tableView.dataSource = self
    }
    
    private func setColorDisplay(on parent: UIView, currentColor: UIColor?) {
        let view = UIView()
        let edge = parent.frame.height * 0.7
        
        view.frame = CGRect(x: parent.frame.width - edge - 20,
                            y: parent.frame.center.y - edge / 2,
                            width: edge,
                            height: edge)
        
        view.layer.borderColor = UIColor.lightGray.cgColor
        view.layer.borderWidth = 1
        view.backgroundColor = currentColor ?? .white
        
        view.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(view)
        view.layoutIfNeeded()
        view.layer.cornerRadius = edge / 2
        
        parent.addConstraints([
            NSLayoutConstraint(item: view,
                               attribute: .width,
                               relatedBy: .equal,
                               toItem: parent,
                               attribute: .width,
                               multiplier: 0,
                               constant: edge),
            
            NSLayoutConstraint(item: view,
                               attribute: .height,
                               relatedBy: .equal,
                               toItem: parent,
                               attribute: .height,
                               multiplier: 0,
                               constant: edge),
            
            NSLayoutConstraint(item: view,
                               attribute: .right,
                               relatedBy: .equal,
                               toItem: parent,
                               attribute: .right,
                               multiplier: 1.0,
                               constant: -20),
            
            NSLayoutConstraint(item: view,
                               attribute: .centerY,
                               relatedBy: .equal,
                               toItem: parent,
                               attribute: .centerY,
                               multiplier: 1.0,
                               constant: 0)
        ])
    }
    
    // MARK: TableViewDelegate
    
    public override func numberOfSections(in tableView: UITableView) -> Int {
        return tables.keys.count
    }
    
    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sections[section]
    }
    
    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        return tables[section]?.count ?? 0
    }
    
    public override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        view.tintColor = .clear
    }
    
    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell()
        
        guard let section = Section(rawValue: indexPath.section),
            let tables = tables[section],
            indexPath.row < tables.count else { return cell }
        
        let table = tables[indexPath.row]
        cell.textLabel?.text = table.title
        
        if table.type == .Color {
            setColorDisplay(on: cell, currentColor: table.currentColor)
        }
        
        return cell
    }
}

extension ThemeViewController {
    fileprivate enum Section: Int {
        case General = 0
        case Post = 1
        case Renote = 2
        case Reply = 3
        case Notifications = 4
    }
    
    fileprivate enum TableType {
        case Color
        case Size
        case Mock // セクションの種類で識別する
    }
    
    fileprivate struct Table {
        var title: String = ""
        var type: TableType = .Color
        
        var currentColor: UIColor?
    }
}
