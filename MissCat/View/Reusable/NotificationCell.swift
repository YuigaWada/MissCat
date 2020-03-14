//
//  NotificationCell.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/24.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxDataSources
import RxSwift
import UIKit

public class NotificationCell: UITableViewCell, UITextViewDelegate {
    @IBOutlet weak var iconImageView: UIImageView!
    
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var usernameLabel: UILabel!
    
    @IBOutlet weak var agoLabel: UILabel!
    @IBOutlet weak var noteView: MisskeyTextView!
    
    @IBOutlet weak var typeIconView: UILabel!
    @IBOutlet weak var typeLabel: UILabel!
    
    public var delegate: NoteCellDelegate?
    
    private let viewModel = NotificationCellViewModel()
    private lazy var emojiView = self.generateEmojiView()
    
    //    private let defaultIconColor =
    private lazy var reactionIconColor = UIColor(red: 231 / 255, green: 76 / 255, blue: 60 / 255, alpha: 1)
    private lazy var renoteIconColor = UIColor(red: 46 / 255, green: 204 / 255, blue: 113 / 255, alpha: 1)
    
    private var emojiViewOnView: Bool = false
    private var disposeBag = DisposeBag()
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        setupComponents()
    }
    
    private func setupComponents() {
        iconImageView.layer.cornerRadius = iconImageView.frame.height / 2
        noteView.delegate = self
        noteView.textColor = .lightGray
        
        typeIconView.font = .awesomeSolid(fontSize: 14.0)
        
        guard !emojiViewOnView else { return }
        addSubview(emojiView)
        emojiViewOnView = true
    }
    
    public func initialize() {
        iconImageView.image = nil
        nameLabel.text = nil
        usernameLabel.text = nil
        agoLabel.text = nil
        noteView.attributedText = nil
        typeIconView.text = nil
        typeLabel.text = nil
        
        emojiView.isHidden = false
        emojiView.initialize()
    }
    
    public func shapeCell(item: NotificationCell.Model) -> NotificationCell {
        guard let username = item.fromUser.username else { return self }
        
        initialize() // セルの再利用のために各パーツを初期化しておく
        
        // font
        noteView.font = UIFont(name: "Helvetica",
                               size: 11.0)
        
        // アイコン画像をset
        if let image = Cache.shared.getIcon(username: username) {
            iconImageView.image = image
        } else if let iconImageUrl = item.fromUser.avatarUrl, let iconUrl = URL(string: iconImageUrl) {
            iconUrl.toUIImage { [weak self] image in
                guard let self = self, let image = image else { return }
                
                DispatchQueue.main.async {
                    Cache.shared.saveIcon(username: username, image: image) // CHACHE!
                    self.iconImageView.image = image
                }
            }
        }
        
        // general
        let displayName = (item.fromUser.name ?? "") == "" ? item.fromUser.username : item.fromUser.name // user.nameがnilか""ならusernameで代替
        
        nameLabel.text = displayName
        usernameLabel.text = "@" + (item.fromUser.username ?? "")
        agoLabel.text = item.ago.calculateAgo()
        
        if let myNote = item.myNote {
            // note
            noteView.attributedText = viewModel.shapeNote(note: myNote.note.mfmPreTransform(),
                                                          isReply: myNote.isReply)
            
            // file
            let fileCount = myNote.files.count
            if fileCount > 0 {
                noteView.attributedText = noteView.attributedText + NSAttributedString(string: "\n> \(fileCount)個の画像 ")
            }
        }
        
        // renote
        if item.type == .renote {
            typeIconView.text = "retweet"
            typeIconView.textColor = renoteIconColor
            typeLabel.text = "Renote"
            emojiView.isHidden = true
        }
        
        // reaction
        else if let reaction = item.reaction {
            typeIconView.text = "fire-alt"
            typeIconView.textColor = reactionIconColor
            typeLabel.text = "Reaction"
            emojiView.emoji = EmojiHandler.convert2EmojiModel(raw: reaction)
        }
        
        setupGesture(item: item)
        
        return self
    }
    
    private func setupGesture(item: NotificationCell.Model) {
        setTapGesture(disposeBag, closure: {
            guard let noteModel = item.myNote else { return }
            self.delegate?.move2PostDetail(item: noteModel)
        })
        
        // リアクションした者のプロフィールを表示
        for aboutReactee in [nameLabel, usernameLabel, iconImageView] {
            aboutReactee?.setTapGesture(disposeBag, closure: {
                self.delegate?.move2Profile(userId: item.fromUser.id)
            })
        }
    }
    
    private func generateEmojiView() -> EmojiView {
        let emojiView = EmojiView()
        
        let sqrt2 = 1.41421356237
        let cos45 = CGFloat(sqrt2 / 2)
        
        let r = iconImageView.frame.width / 2
        let emojiViewRadius = 2 / 3 * r
        
        let basePosition = iconImageView.frame.origin
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

// MARK: NotificationCell.Model

extension NotificationCell {
    public struct Model: IdentifiableType, Equatable {
        public typealias Identity = String
        public let identity: String = String(Float.random(in: 1 ..< 100))
        
        var notificationId: String
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
