//
//  Note.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/12.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit
import WebKit
import RxSwift
import RxDataSources
import MisskeyKit
import Agrume
import SkeletonView

public protocol NoteCellDelegate {
    func tappedReply()
    func tappedRenote()
    func tappedReaction(noteId: String, iconUrl: String?, displayName: String, username: String, note: NSAttributedString, hasFile: Bool, hasMarked: Bool)
    func tappedOthers()
    
    func tappedLink(text: String)
    func move2Profile(userId: String)
}

public class NoteCell: UITableViewCell, UITextViewDelegate, ReactionCellDelegate {
    
    //MARK: IBOutlet (UIView)
    @IBOutlet weak var displayNameLabel: UILabel!
    
    @IBOutlet weak var iconView: UIImageView!
    @IBOutlet weak var usernameLabel: UILabel!
    @IBOutlet weak var agoLabel: UILabel!
    
    @IBOutlet weak var noteView: UITextView!
    
    
    @IBOutlet weak var fileImageView: UIStackView!
    @IBOutlet weak var fileImageContainer: UIView!
    
    @IBOutlet weak var reactionsStackView: UIStackView!
    
    @IBOutlet weak var replyButton: UIButton!
    @IBOutlet weak var renoteButton: UIButton!
    @IBOutlet weak var reactionButton: UIButton!
    @IBOutlet weak var othersButton: UIButton!
    
    @IBOutlet weak var separatorBorder: UIView!
    @IBOutlet weak var replyIndicator: UIView!
    
    @IBOutlet weak var mainStackView: UIStackView!
    
    
    //MARK: IBOutlet (Constraint)
    @IBOutlet weak var displayName2MainStackConstraint: NSLayoutConstraint!
    @IBOutlet weak var icon2MainStackConstraint: NSLayoutConstraint!
    
    
    
    
    
    
    //MARK: Public Var
    public var delegate: NoteCellDelegate?
    public var noteId: String?
    public var userId: String?
    public var iconImageUrl: String?
    
    public var isDetailMode: Bool = false {//投稿の詳細表示もこのNoteCellが担う
        didSet {
            guard isDetailMode else { return }
            
            // If isDetailMode == true ...
            
            // Constraint
            displayName2MainStackConstraint.isActive = false
            icon2MainStackConstraint.isActive = false
        }
    }
    public var isReplyTarget: Bool = false  { // リプライ先の投稿であるかどうか
        didSet {
            guard self.isReplyTarget else { return }
            
            self.backgroundColor = self.replyTargetColor
            
            self.separatorBorder.isHidden = true
            self.replyIndicator.isHidden = false
        }
    }
    
    
    
    
    //MARK: Private Var
    private let disposeBag = DisposeBag()
    private let replyTargetColor = UIColor(hex: "f0f0f0")
    
    private var viewModel = NoteCellViewModel()
    
    
    //MARK: Life Cycle
    override public func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority, verticalFittingPriority: UILayoutPriority) -> CGSize {
        contentView.bounds.size = targetSize
        contentView.layoutIfNeeded()
        return super.systemLayoutSizeFitting(targetSize,
                                             withHorizontalFittingPriority: horizontalFittingPriority,
                                             verticalFittingPriority: verticalFittingPriority)
    }
    
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        self.setupComponents()
    }
    
    private func setupComponents() {
        //["FontAwesome5Free-Solid", "FontAwesome5Free-Regular"], ["FontAwesome5Brands-Regular"]
        
        self.iconView.layer.cornerRadius = self.iconView.frame.height / 2
        self.replyButton.titleLabel?.font = .awesomeSolid(fontSize: 15.0)
        self.renoteButton.titleLabel?.font = .awesomeSolid(fontSize: 15.0)
        self.reactionButton.titleLabel?.font = .awesomeSolid(fontSize: 15.0)
        self.othersButton.titleLabel?.font = .awesomeSolid(fontSize: 15.0)
        
        self.noteView.delegate = self
        
        
        
        if self.fileImageView.arrangedSubviews.count > 0 {
            self.fileImageContainer.translatesAutoresizingMaskIntoConstraints = false
        }
        
        setupSkeltonMode()
        setupProfileGesture() // プロフィールに飛ぶtapgestureを設定する
    }
    
    private func setupProfileGesture() {
        let gestureTargets = [iconView, usernameLabel, displayNameLabel]
        
        gestureTargets.forEach {
            guard let view = $0 else { return }
            
            let tapGesture = UITapGestureRecognizer()
            
            tapGesture.rx.event.bind{ _ in
                guard let delegate = self.delegate, let userId = self.userId else { return }
                delegate.move2Profile(userId: userId)
            }.disposed(by: self.disposeBag)
            
            view.isUserInteractionEnabled = true
            view.addGestureRecognizer(tapGesture)
        }
    }
    
    private func changeStateFileImage(isHidden: Bool) {
        self.fileImageView.isHidden = isHidden
        self.fileImageContainer.isHidden = isHidden
    }
    
    //MARK: Public Methods
    public func initialize(hasFile: Bool) {
        
        self.viewModel = NoteCellViewModel()
        
        self.delegate = nil
        self.noteId = nil
        self.userId = nil
        self.isReplyTarget = false
        
        self.backgroundColor = .white
        self.separatorBorder.isHidden = false
        self.replyIndicator.isHidden = true
        
        self.displayNameLabel.text = nil
        self.usernameLabel.text = nil
        self.iconView.image = nil
        self.agoLabel.text = nil
        self.noteView.attributedText = nil
        
        self.reactionsStackView.isHidden = false
        self.reactionsStackView.arrangedSubviews.forEach{ $0.removeFromSuperview() }
        self.reactionsStackView.subviews.forEach({ $0.removeFromSuperview() })
        
        self.fileImageView.arrangedSubviews.forEach{ $0.removeFromSuperview() }
        self.fileImageView.subviews.forEach({ $0.removeFromSuperview() })
        
        //TODO: reactionを隠す時これつかう → UIView.animate(withDuration: 0.25, animations: { () -> Void in
        
        
        self.changeStateFileImage(isHidden: !hasFile)
        
        
        self.replyButton.setTitle("", for: .normal)
        self.renoteButton.setTitle("", for: .normal)
        self.reactionButton.setTitle("", for: .normal)
        
//        changeSkeltonState(on: true)
    }
    
    public func setupFileImage(_ image: UIImage, originalImageUrl: String) {
        //self.changeStateFileImage(isHidden: false) //メインスレッドでこれ実行するとStackViewの内部計算と順番が前後するのでダメ
        
        let tapGesture = UITapGestureRecognizer()
        tapGesture.rx.event.bind{ _ in
            originalImageUrl.toUIImage{ image in
                guard let image = image, let delegate = self.delegate as? UIViewController else { return }
                
                DispatchQueue.main.async {
                    let agrume = Agrume(image: image)
                    agrume.show(from: delegate) // 画像を表示
                }
            }
        }.disposed(by: self.disposeBag)
        
        
        DispatchQueue.main.async {
            let imageView = UIImageView(image: image)
            imageView.contentMode = .center
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = 10
            imageView.isUserInteractionEnabled = true
            //tap gestureを付加する
            imageView.addGestureRecognizer(tapGesture)
            
            
            self.fileImageView.addArrangedSubview(imageView)
            self.mainStackView.setNeedsLayout()
        }
    }
    
    
    public func shapeCell(item: NoteCell.Model)-> NoteCell {
        guard let noteId = item.noteId else { return NoteCell() }
        self.initialize(hasFile: item.files.count > 0) // Initialize because NoteCell is reused by TableView.
        
        
        //main
        let cachedNote = Cache.shared.getNote(noteId: noteId) // セルが再利用されるのでキャッシュは中央集権的に
        let hasCachedNote: Bool = cachedNote != nil
        
        
        self.isReplyTarget = item.isReplyTarget
        
        self.noteId = item.noteId
        self.userId = item.userId
        self.agoLabel.text = item.ago.calculateAgo()
        self.displayNameLabel.text = item.displayName
        self.usernameLabel.text = "@" + item.username
        self.noteView.attributedText = viewModel.shapeNote(identifier: item.identity,
                                                           note: item.note,
                                                           cache: hasCachedNote ? cachedNote : nil,
                                                           isReply: item.isReply,
                                                           externalEmojis: item.emojis,
                                                           isDetailMode: isDetailMode)
        
        if !hasCachedNote {
            Cache.shared.saveNote(noteId: noteId, note: self.noteView.attributedText) // CHACHE!
        }
        
        
        if let image = Cache.shared.getIcon(username: item.username) {
            self.iconView.image = image
        }
        else if let iconImageUrl = item.iconImageUrl, let iconUrl = URL(string: iconImageUrl) {
            self.iconImageUrl = iconImageUrl
            
            iconUrl.toUIImage{ [weak self] image in
                guard let self = self, let image = image else { return }
                
                DispatchQueue.main.async {
                    Cache.shared.saveIcon(username: item.username, image: image) // CHACHE!
                    self.iconView.image = image
                }
            }
        }
        
        //file
        if let files = Cache.shared.getFiles(noteId: noteId) {
            files.forEach{ self.setupFileImage($0.thumbnail, originalImageUrl: $0.originalUrl) }
        }
        else {
            item.files.filter{ $0 != nil }.forEach { file in
                guard let thumbnailUrl = file!.thumbnailUrl, let original = file!.url else { return }
                
                thumbnailUrl.toUIImage { image in
                    guard let image = image else { return }
                    Cache.shared.saveFiles(noteId: noteId, image: image, originalUrl: original)
                    self.setupFileImage(image, originalImageUrl: original)
                }
            }
        }
        
        
        //footer
        let replyCount = item.replyCount != 0 ? String(item.replyCount) : ""
        let renoteCount = item.renoteCount != 0 ? String(item.renoteCount) : ""
        var reactionsCount: Int = 0
        item.reactions.forEach{
            guard let reaction = $0 else { return }
            reactionsCount += Int(reaction.count ?? "0") ?? 0
        }
        
        self.replyButton.setTitle("reply\(replyCount)", for: .normal)
        self.renoteButton.setTitle("retweet\(renoteCount)", for: .normal)
        self.reactionButton.setTitle("plus\(reactionsCount == 0 ? "" : String(reactionsCount))", for: .normal)
        
        
        //reaction
        guard self.reactionsStackView.arrangedSubviews.count < 10 else {
            return self
        }
        
        var marginCount = 5 - item.reactions.count
        
        item.reactions.forEach { reaction in
            guard let reaction = reaction, let count = reaction.count, let rawEmoji = reaction.name, !count.isZero() else {
                marginCount += 1
                return
            }
            
            let isMyReaction = item.myReaction == rawEmoji
            
            guard let convertedEmojiData = EmojiHandler.handler.convertEmoji(raw: rawEmoji) else
            {
                //If being not converted
                let reactionCell = ReactionCell()
                reactionCell.delegate = self
                
                reactionCell.setup(noteId: item.noteId, count: count, rawDefaultEmoji: rawEmoji, isMyReaction: isMyReaction, rawReaction: rawEmoji)
                self.reactionsStackView.addArrangedSubview(reactionCell)
                
                return
            }
            
            let reactionCell = ReactionCell()
            reactionCell.delegate = self
            
            switch convertedEmojiData.type {
            case "default":
                reactionCell.setup(noteId: item.noteId, count: count, defaultEmoji: convertedEmojiData.emoji, isMyReaction: isMyReaction, rawReaction: rawEmoji)
            case "custom":
                reactionCell.setup(noteId: item.noteId, count: count, customEmoji: convertedEmojiData.emoji, isMyReaction: isMyReaction, rawReaction: rawEmoji)
            default:
                return
            }
            self.reactionsStackView.addArrangedSubview(reactionCell)
        }
        
        
        if marginCount > 0 {
            for _ in 1...marginCount {
                let reactionCell = ReactionCell()
                reactionCell.alpha =  0
                
                self.reactionsStackView.addArrangedSubview(reactionCell)
            }
        }
        
        let isEmptyReaction = marginCount == 5
        if isEmptyReaction {
            self.reactionsStackView.isHidden = true
        }
        
        
        
//        changeSkeltonState(on: false)
        return self
    }
    
    //MARK: Utilities
    private func setupSkeltonMode() {
        self.separatorBorder.isSkeletonable = true
        self.replyIndicator.isSkeletonable = true
        
        self.displayNameLabel.isSkeletonable = true
        self.usernameLabel.isSkeletonable = true
        self.iconView.isSkeletonable = true
        self.agoLabel.isSkeletonable = true
        self.noteView.isSkeletonable = true
        
        self.reactionsStackView.isSkeletonable = true
        self.fileImageView.isSkeletonable = true
    }
    
    
    private func changeSkeltonState(on: Bool) {
        if on {
            self.separatorBorder.showAnimatedSkeleton()
            self.replyIndicator.showAnimatedSkeleton()
            
            self.displayNameLabel.showAnimatedSkeleton()
            self.usernameLabel.showAnimatedSkeleton()
            self.iconView.showAnimatedSkeleton()
            self.agoLabel.showAnimatedSkeleton()
            self.noteView.showAnimatedSkeleton()
            
            self.reactionsStackView.showAnimatedSkeleton()
            self.fileImageView.showAnimatedSkeleton()
        }
        else {
            self.separatorBorder.hideSkeleton()
            self.replyIndicator.hideSkeleton()
            
            self.displayNameLabel.hideSkeleton()
            self.usernameLabel.hideSkeleton()
            self.iconView.hideSkeleton()
            self.agoLabel.hideSkeleton()
            self.noteView.hideSkeleton()
            
            self.reactionsStackView.hideSkeleton()
            self.fileImageView.hideSkeleton()
        }
    }
    
    
    
    //MARK: DELEGATE
    public func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        
        if let delegate = delegate {
            delegate.tappedLink(text: URL.absoluteString)
        }
        
        return false
    }
    
    public func tappedReaction(noteId: String, reaction: String, isRegister: Bool) {
        if isRegister {
            viewModel.registerReaction(noteId: noteId, reaction: reaction)
        }
        else {
            viewModel.cancelReaction(noteId: noteId)
        }
    }
    
    
    //MARK: IBAction
    @IBAction func tappedReply(_ sender: Any) {
        guard let delegate = delegate else { return }
        delegate.tappedReply()
    }
    
    @IBAction func tappedRenote(_ sender: Any) {
        guard let delegate = delegate else { return }
        delegate.tappedRenote()
    }
    
    @IBAction func tappedReaction(_ sender: Any) {
        guard let delegate = delegate, let noteId = self.noteId, let username = self.usernameLabel.text, username.count > 1 else { return }
        
        delegate.tappedReaction(noteId: noteId,
                                iconUrl: self.iconImageUrl,
                                displayName: self.displayNameLabel.text ?? "",
                                username: String(username.suffix(username.count-1)),
                                note: self.noteView.attributedText,
                                hasFile: false,
                                hasMarked: false)
        
    }
    
    @IBAction func tappedOthers(_ sender: Any) {
        guard let delegate = delegate else { return }
        delegate.tappedOthers()
    }
}




//MARK: NoteCell.Model
extension NoteCell {
    public struct Model: IdentifiableType, Equatable {
        
        var isReactionGenCell = false
        var isRenoteeCell = false
        var renotee: String? = nil
        var baseNoteId: String? = nil // どのcellに対するReactionGenCellなのか
        var isReply: Bool = false // リプライであるかどうか
        var isReplyTarget: Bool = false // リプライ先の投稿であるかどうか
        
        public let identity: String = String(Float.random(in: 1 ..< 100))
        let noteId: String?
        
        public typealias Identity = String
        
        let iconImageUrl: String?
        var iconImage: UIImage?
        
        let userId: String
        let displayName: String
        let username: String
        let note: String
        let ago: String
        let replyCount: Int
        let renoteCount: Int
        var reactions: [ReactionCount?]
        var myReaction: String?
        let files: [File?]
        let emojis: [EmojiModel?]?
        
        public static func == (lhs: NoteCell.Model, rhs: NoteCell.Model) -> Bool {
            return lhs.identity == rhs.identity
        }
        
//        static func fakeReactionGenCell(baseNoteId: String)-> NoteCell.Model {
//            return NoteCell.Model(isReactionGenCell: true,
//                                  baseNoteId: baseNoteId,
//                                  noteId: "",
//                                  iconImageUrl: "",
//                                  iconImage: nil,
//                                  displayName: "",
//                                  username: "",
//                                  note: "",
//                                  ago: "",
//                                  replyCount: 0,
//                                  renoteCount: 0,
//                                  reactions: [],
//                                  myReaction: nil,
//                                  files: [],
//                                  emojis: [])
//        }

        static func fakeRenoteecell(renotee: String, baseNoteId: String)-> NoteCell.Model {
            
            var renotee = renotee
            if renotee.count > 7 {
                renotee = String(renotee.prefix(10)) + "..."
            }
            
            return NoteCell.Model(isRenoteeCell: true,
                                  renotee: renotee,
                                  baseNoteId: baseNoteId,
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
                                  myReaction: nil,
                                  files: [],
                                  emojis: [])
            
        }
        
    }
    
    struct Section {
        var items: [Model]
    }
    
}

extension NoteCell.Section: AnimatableSectionModelType {
    
    typealias Item = NoteCell.Model
    typealias Identity = String
    
    
    public var identity: String {
        return ""
    }
    
    init(original: NoteCell.Section, items: [NoteCell.Model]) {
        self = original
        self.items = items
    }
}
