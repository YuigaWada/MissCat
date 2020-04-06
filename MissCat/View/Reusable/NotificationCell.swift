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

class NotificationCell: UITableViewCell, UITextViewDelegate {
    @IBOutlet weak var iconImageView: UIImageView!
    
    @IBOutlet weak var nameTextView: MisskeyTextView!
    
    @IBOutlet weak var agoLabel: UILabel!
    @IBOutlet weak var noteView: MisskeyTextView!
    
    @IBOutlet weak var followButton: UIButton! // APIがフォロー済みかどうかの情報をワタシてくれないので一時的に「くわしくボタン」へ変更
    @IBOutlet weak var typeIconView: UILabel!
    @IBOutlet weak var typeLabel: UILabel!
    @IBOutlet weak var defaultNoteBottomConstraint: NSLayoutConstraint!
    
    var delegate: NoteCellDelegate?
    
    private let viewModel = NotificationCellViewModel()
    private lazy var emojiView = self.generateEmojiView()
    
    //    private let defaultIconColor =
    private lazy var reactionIconColor = UIColor(red: 231 / 255, green: 76 / 255, blue: 60 / 255, alpha: 1)
    private lazy var renoteIconColor = UIColor(red: 46 / 255, green: 204 / 255, blue: 113 / 255, alpha: 1)
    
    private var emojiViewOnView: Bool = false
    private var disposeBag = DisposeBag()
    
    override func layoutSubviews() {
        super.layoutSubviews()
        setupComponents()
        nameTextView.transformText()
        
        // MEMO: MisskeyApiの "i/notifications"はfromUserの自己紹介を流してくれないので、対応するまで非表示にする
//        noteView.transformText()
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
    
    func initialize() {
        iconImageView.image = nil
        agoLabel.text = nil
        noteView.attributedText = nil
        typeIconView.text = nil
        typeLabel.text = nil
        
        nameTextView.attributedText = nil
        nameTextView.resetViewString()
        
        emojiView.isHidden = false
        emojiView.initialize()
        
        followButton.isHidden = true
    }
    
    func shapeCell(item: NotificationCell.Model) -> NotificationCell {
        if !item.isMock, item.fromUser?.username == nil {
            return self
        }
        
        let username = item.fromUser?.username ?? ""
        
        initialize() // セルの再利用のために各パーツを初期化しておく
        
        // font
        noteView.font = UIFont(name: "Helvetica",
                               size: 11.0)
        
        // アイコン画像をset
        if let image = Cache.shared.getIcon(username: username) {
            iconImageView.image = image
        } else if let iconImageUrl = item.fromUser?.avatarUrl, let iconUrl = URL(string: iconImageUrl) {
            iconUrl.toUIImage { [weak self] image in
                guard let self = self, let image = image else { return }
                
                DispatchQueue.main.async {
                    Cache.shared.saveIcon(username: username, image: image) // CHACHE!
                    self.iconImageView.image = image
                }
            }
        }
        
        // general
        
        nameTextView.attributedText = item.shapedDisplayName?.attributed
        item.shapedDisplayName?.mfmEngine.renderCustomEmojis(on: nameTextView)
        
        agoLabel.text = item.ago.calculateAgo()
        
        if let myNote = item.myNote {
            // note
            noteView.attributedText = item.myNote?.shapedNote?.attributed
            
            // file
            let fileCount = myNote.files.count
            if fileCount > 0 {
                noteView.attributedText = noteView.attributedText + NSAttributedString(string: "\n> \(fileCount)個のファイル ")
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
        
        // follow
        else if item.type == .follow {
            typeIconView.text = "user-friends"
            typeIconView.textColor = .systemBlue
            typeLabel.text = "Follow"
            emojiView.isHidden = true
            followButton.isHidden = false
            // MEMO: MisskeyApiの "i/notifications"はfromUserの自己紹介を流してくれないので、対応するまで非表示にする
            
//            noteView.attributedText = item.shapedDescritpion?.attributed
//            item.shapedDescritpion?.mfmEngine.renderCustomEmojis(on: noteView)
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
        for aboutReactee in [nameTextView, iconImageView, emojiView, followButton] {
            aboutReactee?.setTapGesture(disposeBag, closure: {
                guard let userId = item.fromUser?.id else { return }
                self.delegate?.move2Profile(userId: userId)
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
    class Model: IdentifiableType, Equatable {
        internal init(isMock: Bool = false, notificationId: String, type: ActionType = .reply, shapedDisplayName: MFMString? = nil, myNote: NoteCell.Model?, replyNote: NoteCell.Model?, fromUser: UserModel?, reaction: String?, ago: String) {
            self.isMock = isMock
            self.notificationId = notificationId
            self.type = type
            self.shapedDisplayName = shapedDisplayName
            self.myNote = myNote
            self.replyNote = replyNote
            self.fromUser = fromUser
            self.reaction = reaction
            self.ago = ago
        }
        
        typealias Identity = String
        let identity: String = String(Float.random(in: 1 ..< 100))
        
        var isMock: Bool = false
        
        var notificationId: String
        var type: ActionType = .reply
        
        var shapedDisplayName: MFMString?
        var shapedDescritpion: MFMString?
        
        let myNote: NoteCell.Model? // 自分のどの投稿に対してか
        let replyNote: NoteCell.Model? // 相手の投稿
        
        let fromUser: UserModel?
        
        let reaction: String?
        
        let ago: String
        
        static func == (lhs: NotificationCell.Model, rhs: NotificationCell.Model) -> Bool {
            return lhs.identity == rhs.identity
        }
    }
    
    struct Section {
        var items: [Model]
    }
}

extension NotificationCell.Section: AnimatableSectionModelType {
    typealias Item = NotificationCell.Model
    typealias Identity = String
    
    var identity: String {
        return ""
    }
    
    init(original: NotificationCell.Section, items: [NotificationCell.Model]) {
        self = original
        self.items = items
    }
}
