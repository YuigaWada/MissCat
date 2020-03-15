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
    }
    
    private func setTables() {
        // <テーマ>
        // 一般
        // ・メインカラー default: .systemBlue
        // ・背景色 default: .white
        // ・境界線 default:  gray
        //
        tables[.General] = [.init(title: "メインカラー", currentColor: .systemBlue),
                            .init(title: "背景色", currentColor: .white),
                            .init(title: "境界線", currentColor: .lightGray)]
        
        // 投稿
        //
        // [投稿のMock]
        //
        // ・文字色 text
        // ・リンク色 link
        // ・リアクション
        // ・自分のリアクション
        // ・文字サイズ
        //
        
        tables[.Post] = [.init(type: .Mock),
                         .init(title: "文字色", currentColor: .systemBlue),
                         .init(title: "リンク色", currentColor: .white),
                         .init(title: "リアクションセル", currentColor: .lightGray),
                         .init(title: "自分のリアクション", currentColor: .lightGray),
                         .init(title: "文字サイズ", type: .Size)]
        
        // [引用RNのMock]
        // [RNのMock]
        //
        // ・Renote文字 renote
        // ・引用RNのボーダー comment-renote-border
        //
        //
        
        tables[.Renote] = [.init(type: .Mock),
                           .init(title: "Renoteしたユーザー名", currentColor: .systemBlue),
                           .init(title: "引用RNのボーダー", currentColor: .white)]
        
        // [リプライのMock]
        //
        // ・ 背景 reply-background
        // ・文字色 reply-text
        //
        
        tables[.Reply] = [.init(type: .Mock),
                          .init(title: "背景", currentColor: .white),
                          .init(title: "文字色", currentColor: .lightGray)]
        
        // 通知欄
        //
        // [通知のMock]
        //
        // ・リアクション
        // ・RN
        // ・文字色
        tables[.Notifications] = [.init(type: .Mock),
                                  .init(title: "リアクション", currentColor: .systemBlue),
                                  .init(title: "Renote", currentColor: .white),
                                  .init(title: "文字色", currentColor: .lightGray)]
    }
    
    private func setColorDisplay(on parent: UIView, currentColor: UIColor?) {
        let view = UIView()
        let edge = self.view.frame.height * 0.7
        
        view.frame = CGRect(x: self.view.frame.origin.x - edge - 20,
                            y: self.view.frame.center.y - edge / 2,
                            width: edge,
                            height: edge)
        
        view.layer.borderColor = UIColor.lightGray.cgColor
        view.layer.borderWidth = 1
        view.backgroundColor = currentColor ?? .white
        
        parent.addSubview(view)
        view.layoutIfNeeded()
        view.layer.cornerRadius = edge / 2
    }
    
    // MARK: TableViewDelegate
    
    public func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return tables.keys.count
    }
    
    public func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sections[section]
    }
    
    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell()
        
        guard let section = Section(rawValue: indexPath.section),
            let tables = tables[section] else { return cell }
        
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
