//
//  NotificationCell.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/24.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit
import RxDataSources
import RxSwift
import MisskeyKit

public class NotificationCell: UITableViewCell, UITextViewDelegate {
    
    @IBOutlet weak var iconImageView: UIImageView!
    
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var usernameLabel: UILabel!
    
    @IBOutlet weak var agoLabel: UILabel!
    @IBOutlet weak var noteView: MisskeyTextView!
    
    @IBOutlet weak var typeIconView: UILabel!
    @IBOutlet weak var typeLabel: UILabel!
    
    private let viewModel = NotificationCellViewModel()
    private lazy var emojiView = self.generateEmojiView()

    private var emojiViewOnView: Bool = false
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        self.setupComponents()
    }
    
    private func setupComponents() {
        self.iconImageView.layer.cornerRadius = self.iconImageView.frame.height / 2
        self.noteView.delegate = self
        self.noteView.textColor = .lightGray
        
        self.typeIconView.font = .awesomeSolid(fontSize: 14.0)
        
        guard !emojiViewOnView else { return }
        self.addSubview(emojiView)
        self.emojiViewOnView = true
    }
    
    
    public func initialize() {
        self.iconImageView.image = nil
        self.nameLabel.text = nil
        self.usernameLabel.text = nil
        self.agoLabel.text = nil
        self.noteView.attributedText = nil
        self.typeIconView.text = nil
        self.typeLabel.text = nil
        
        self.emojiView.isHidden = false
        self.emojiView.initialize()
    }
    
    
    
    public func shapeCell(item: NotificationCell.Model)-> NotificationCell {
        guard let username = item.fromUser.username else { return self }
        
        self.initialize() // セルの再利用のために各パーツを初期化しておく
        
        //アイコン画像をset
        if let image = Cache.shared.getIcon(username: username) {
            self.iconImageView.image = image
        }
        else if let iconImageUrl = item.fromUser.avatarUrl, let iconUrl = URL(string: iconImageUrl) {
            iconUrl.toUIImage{ [weak self] image in
                guard let self = self, let image = image else { return }
                
                DispatchQueue.main.async {
                    Cache.shared.saveIcon(username: username, image: image) // CHACHE!
                    self.iconImageView.image = image
                }
            }
        }
        
        //general
        let displayName = (item.fromUser.name ?? "") == "" ? item.fromUser.username : item.fromUser.name // user.nameがnilか""ならusernameで代替
        
        self.nameLabel.text = displayName
        self.usernameLabel.text = "@" + (item.fromUser.username ?? "")
        self.agoLabel.text = item.ago.calculateAgo()
        
        if let myNote = item.myNote, let noteId = myNote.noteId {
            
            // note
            let cachedNote = Cache.shared.getNote(noteId: noteId)
            let hasCachedNote: Bool = cachedNote != nil
            
            //キャッシュを活用する
            self.noteView.attributedText = hasCachedNote ? cachedNote : viewModel.shapeNote(identifier: item.identity,
                                                                                            note: myNote.note,
                                                                                            isReply: myNote.isReply,
                                                                                            externalEmojis: myNote.emojis)
            //キャッシュが存在しなければキャッシュしておく
            if !hasCachedNote { Cache.shared.saveNote(noteId: noteId, note: self.noteView.attributedText) }
            
            
            // file
             let fileCount =  myNote.files.count
            if fileCount > 0 {
                self.noteView.attributedText = self.noteView.attributedText + NSAttributedString(string: "\n> \(fileCount)個の画像 ")
            }
        }
        
        // renote
        if item.type == .renote {
            self.typeIconView.text = "retweet"
            self.typeLabel.text = "Renote"
            self.emojiView.isHidden = true
        }
    
        // reaction
        else if let reaction = item.reaction {
            self.typeIconView.text = "fire-alt"
            self.typeLabel.text = "Reaction"
            self.emojiView.emoji = reaction
        }
        
    
        return self
    }
    
    private func generateEmojiView()-> EmojiView {
        let emojiView = EmojiView()
        
        let sqrt2 = 1.41421356237
        let cos45 = CGFloat(sqrt2 / 2)
        
        let r = self.iconImageView.frame.width / 2
        let emojiViewRadius = 2/3 * r
        
        let basePosition = self.iconImageView.frame.origin
        let position = CGPoint(x: basePosition.x + cos45 * r,
                               y: basePosition.y + cos45 * r)
        
        
        
        emojiView.frame = CGRect(x: position.x,
                                 y: position.y,
                                 width: emojiViewRadius * 2,
                                 height: emojiViewRadius * 2)
        
        emojiView.view.layer.backgroundColor = UIColor(hex: "EE7258").cgColor
        emojiView.view.layer.cornerRadius = emojiViewRadius
        
        return emojiView
    }
    
}



//MARK: NotificationCell.Model
extension NotificationCell {
    public struct Model: IdentifiableType, Equatable {
        public typealias Identity = String
        public let identity: String = String(Float.random(in: 1 ..< 100))
        
        var type: ActionType = .reply
        
        let myNote: NoteCell.Model? // 自分のどの投稿に対してか
        let replyNote: NoteCell.Model? // 相手の投稿
        
        let fromUser: UserModel
        
        let reaction: String?
        
        let ago: String
        
        
        public static func == (lhs: NotificationCell.Model, rhs: NotificationCell.Model) -> Bool {
            return lhs.identity == rhs.identity
        }
        
    }
    
    public struct Section {
        public var items: [Model]
    }
    
}

extension NotificationCell.Section: AnimatableSectionModelType {
    
    public typealias Item = NotificationCell.Model
    public typealias Identity = String
    
    
    public var identity: String {
        return ""
    }
    
    public init(original: NotificationCell.Section, items: [NotificationCell.Model]) {
        self = original
        self.items = items
    }
}
