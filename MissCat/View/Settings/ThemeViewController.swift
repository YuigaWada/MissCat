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
    
    private lazy var noteMock: NoteCell? = getNoteCell()
    private lazy var renoteeMock: RenoteeCell? = getRenoteeCell()
    private lazy var renoteMock: NoteCell? = getNoteCell()
    private lazy var commentRenoteMock: NoteCell? = getNoteCell()
    private lazy var replyMock: NoteCell? = getNoteCell()
    private lazy var notificationsMock: NotificationCell? = getNotificationCell()
    
    private lazy var tables: [Section: [Table]] = {
        var _tables = [Section: [Table]]()
        for i in 0 ... 4 { _tables[Section(rawValue: i)!] = [] }
        
        return _tables
    }()
    
    //MARK: LifeCycle
    public override func viewDidLoad() {
        super.viewDidLoad()
        setTables()
        setTableView()
    }
    
    private func setTables() {
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
    
    //MARK: Cell
    
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
    
    private func setMock(of section: Section, on parent: UIView) {
        let stackView = UIStackView()
        
        stackView.alignment = .fill
        stackView.distribution = .fillEqually
        stackView.spacing = 0
        stackView.axis = .vertical
        
        switch section {
        case .General:
            return
        case .Post:
            guard let noteMock = noteMock else { return }
            stackView.addArrangedSubview(noteMock)
            
        case .Renote:
            guard let renoteeMock = renoteeMock,
                let renoteMock = renoteMock,
                let commentRenoteMock = commentRenoteMock else { return }
            stackView.addArrangedSubview(renoteeMock)
            stackView.addArrangedSubview(renoteMock)
            stackView.addArrangedSubview(commentRenoteMock)
            
        case .Reply:
            guard let replyMock = replyMock else { return }
            stackView.addArrangedSubview(replyMock)
        case .Notifications:
            guard let notificationsMock = notificationsMock else { return }
            stackView.addArrangedSubview(notificationsMock)
        }
        stackView.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(stackView)
        
        parent.addConstraints([
            NSLayoutConstraint(item: stackView,
                               attribute: .width,
                               relatedBy: .equal,
                               toItem: parent,
                               attribute: .width,
                               multiplier: 0.8,
                               constant: 0),
            
            NSLayoutConstraint(item: stackView,
                               attribute: .height,
                               relatedBy: .equal,
                               toItem: parent,
                               attribute: .height,
                               multiplier: 0,
                               constant: CGFloat(120 * stackView.arrangedSubviews.count)),
            
            NSLayoutConstraint(item: stackView,
                               attribute: .centerX,
                               relatedBy: .equal,
                               toItem: parent,
                               attribute: .centerX,
                               multiplier: 1.0,
                               constant: 0),
            
            NSLayoutConstraint(item: stackView,
                               attribute: .centerY,
                               relatedBy: .equal,
                               toItem: parent,
                               attribute: .centerY,
                               multiplier: 1.0,
                               constant: 0)
        ])
    }
    

    
    //MARK: Utilities
    
    private func getNoteCell() -> NoteCell? {
        return UINib(nibName: "NoteCell", bundle: nil).instantiate(withOwner: self, options: nil).first as? NoteCell
    }
    
    private func getNotificationCell() -> NotificationCell? {
        return UINib(nibName: "NotificationCell", bundle: nil).instantiate(withOwner: self, options: nil).first as? NotificationCell
    }
    
    private func getRenoteeCell() -> RenoteeCell? {
        return UINib(nibName: "RenoteeCell", bundle: nil).instantiate(withOwner: self, options: nil).first as? RenoteeCell
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
    
    public override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let section = Section(rawValue: indexPath.section),
            let tables = tables[section],
            indexPath.row < tables.count else { return 60 }
        
        let table = tables[indexPath.row]
        let mockCount = section == .Renote ? 2 : 1
        
        return table.type == .Mock ? CGFloat(150 * mockCount) : 60
    }
    
    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell()
        
        guard let section = Section(rawValue: indexPath.section),
            let tables = tables[section],
            indexPath.row < tables.count else { return cell }
        
        let table = tables[indexPath.row]
        cell.textLabel?.text = table.title
        
        switch table.type {
        case .Color:
            setColorDisplay(on: cell, currentColor: table.currentColor)
        case .Size:
            break
        case .Mock:
            setMock(of: section, on: cell)
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
