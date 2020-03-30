//
//  ThemeViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/16.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import UIKit

class ThemeViewController: UITableViewController {
    private var sections = ["一般", "投稿", "Renote", "リプライ", "通知欄"]
    
    private lazy var noteMock = generateMockNoteModel()
    private lazy var renoteeMock = generateMockRenoteeModel()
    private lazy var renoteMock = generateMockNoteModel()
    private lazy var commentRenoteMock = generateMockNoteModel(isCommentRenoteTarget: true)
    private lazy var replyMock = generateMockNoteModel(isReply: true)
    private lazy var notificationsMock = generateMockNotificationModel()
    
    private var noteMockModel: NoteCell.Model?
    private var renoteeMockModel: NoteCell.Model?
    
    private lazy var tables: [Section: [Table]] = {
        var _tables = [Section: [Table]]()
        for i in 0 ... 4 { _tables[Section(rawValue: i)!] = [] }
        
        return _tables
    }()
    
    // MARK: LifeCycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setTables()
        setTableView()
    }
    
    private func setTables() {
        let theme = Theme.shared.getCurrentTheme()
        
        tables[.General] = [.init(title: "メインカラー", currentColor: theme.general.main),
                            .init(title: "背景色", currentColor: theme.general.background),
                            .init(title: "境界線", currentColor: theme.general.border)]
        
        tables[.Post] = [.init(title: "文字色", currentColor: theme.post.text),
                         .init(title: "リンク色", currentColor: theme.post.link),
                         .init(title: "リアクションセル", currentColor: theme.post.reaction),
                         .init(title: "自分のリアクション", currentColor: theme.post.myReaction),
                         .init(title: "文字サイズ", type: .Size),
                         .init(type: .Mock)]
        
        tables[.Renote] = [.init(title: "Renoteしたユーザー名", currentColor: theme.renote.user),
                           .init(title: "引用RNのボーダー", currentColor: theme.renote.commentRNBorder),
                           .init(type: .Mock), .init(type: .Mock), .init(type: .Mock)]
        
        tables[.Reply] = [.init(title: "背景", currentColor: theme.reply.background),
                          .init(title: "文字色", currentColor: theme.reply.text),
                          .init(title: "インディケーター", currentColor: theme.reply.indicator),
                          .init(type: .Mock)]
        
        tables[.Notifications] = [.init(title: "リアクション", currentColor: theme.notifications.reaction),
                                  .init(title: "Renote", currentColor: theme.notifications.renote),
                                  .init(title: "文字色", currentColor: theme.notifications.text),
                                  .init(type: .Mock)]
    }
    
    private func setTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        
        tableView.register(UINib(nibName: "NoteCell", bundle: nil), forCellReuseIdentifier: "NoteMock")
        tableView.register(UINib(nibName: "RenoteeCell", bundle: nil), forCellReuseIdentifier: "RenoteeMock")
        tableView.register(UINib(nibName: "NotificationCell", bundle: nil), forCellReuseIdentifier: "NotificationCell")
    }
    
    // MARK: Cell
    
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
    
    private func generateMockNoteModel(isReply: Bool = false, isCommentRenoteTarget: Bool = false, onOtherNote: Bool = false) -> NoteCell.Model {
        let commentRNModel = isCommentRenoteTarget ? generateMockNoteModel(isCommentRenoteTarget: false, onOtherNote: true) : nil
        let model = NoteCell.Model(isReplyTarget: isReply,
                                   noteId: "",
                                   iconImageUrl: "https://s3.arkjp.net/misskey/1be7b029-31d4-43a2-9fe0-10c608d161af.png",
                                   userId: "",
                                   displayName: "MissCat",
                                   username: "misscat",
                                   note: "MissCatとはiOS向けに開発されたMisskey用クライアントです。",
                                   ago: "0m",
                                   replyCount: 0,
                                   renoteCount: 0,
                                   reactions: [],
                                   shapedReactions: [],
                                   myReaction: "",
                                   files: [],
                                   emojis: [],
                                   commentRNTarget: commentRNModel,
                                   onOtherNote: onOtherNote,
                                   poll: nil)
        
        MFMEngine.shapeModel(model)
        return model
    }
    
    private func generateMockRenoteeModel() -> NoteCell.Model {
        let model = NoteCell.Model(isRenoteeCell: true,
                                   renotee: "misscat",
                                   baseNoteId: "",
                                   noteId: "",
                                   iconImageUrl: "",
                                   iconImage: nil,
                                   userId: "",
                                   displayName: "",
                                   username: "",
                                   note: "",
                                   ago: "",
                                   replyCount: 0,
                                   renoteCount: 0,
                                   reactions: [],
                                   shapedReactions: [],
                                   myReaction: nil,
                                   files: [],
                                   emojis: [],
                                   commentRNTarget: nil,
                                   poll: nil)
        
        return model
    }
    
    private func generateMockNotificationModel() -> NotificationCell.Model {
        return NotificationCell.Model(isMock: true,
                                      notificationId: "",
                                      myNote: generateMockNoteModel(),
                                      replyNote: nil,
                                      fromUser: nil,
                                      reaction: "👍",
                                      ago: "0")
    }
    
    // MARK: TableViewDelegate
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return tables.keys.count
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sections[section]
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        return tables[section]?.count ?? 0
    }
    
    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        view.tintColor = .white
    }
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 70
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let section = Section(rawValue: indexPath.section),
            let tables = tables[section],
            indexPath.row < tables.count else { return 60 }
        
        let table = tables[indexPath.row]
        
        return table.type == .Mock ? UITableView.automaticDimension : 60
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section),
            let tables = tables[section],
            indexPath.row < tables.count else { return UITableViewCell() }
        
        let table = tables[indexPath.row]
        
        switch table.type {
        case .Color:
            let cell = UITableViewCell()
            cell.textLabel?.text = table.title
            setColorDisplay(on: cell, currentColor: table.currentColor)
            return cell
        case .Size:
            let cell = UITableViewCell()
            cell.textLabel?.text = table.title
            return cell
        case .Mock:
            let isRenotee = section == .Renote && indexPath.row == 2
            let isCommentRenote = section == .Renote && indexPath.row == 4
            let isReply = section == .Reply
            let isNotification = section == .Notifications
            
            if isRenotee {
                guard let mock = tableView.dequeueReusableCell(withIdentifier: "RenoteeMock", for: indexPath) as? RenoteeCell
                else { return UITableViewCell() }
                
                mock.setRenotee("misscat")
                mock.selectionStyle = .none // 選択不可能に
                return mock
            } else if isNotification {
                guard let mock = tableView.dequeueReusableCell(withIdentifier: "NotificationCell", for: indexPath) as? NotificationCell
                else { return UITableViewCell() }
                
                mock.selectionStyle = .none // 選択不可能に
                return mock.shapeCell(item: notificationsMock)
            }
            
            guard let mock = tableView.dequeueReusableCell(withIdentifier: "NoteMock", for: indexPath) as? NoteCell
            else { return UITableViewCell() }
            
            var model: NoteCell.Model
            if isCommentRenote { model = commentRenoteMock }
            else if isReply { model = replyMock }
            else { model = noteMock }
            
            _ = mock.transform(with: .init(item: model))
            
            mock.selectionStyle = .none // 選択不可能に
            return mock
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let viewController = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "404-page")
        navigationController?.pushViewController(viewController, animated: true)
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
