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
import RxCocoa
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

fileprivate typealias ViewModel = NoteCellViewModel
public class NoteCell: UITableViewCell, UITextViewDelegate, ReactionCellDelegate {
    
    //MARK: IBOutlet (UIView)
    
    @IBOutlet weak var nameTextView: MisskeyTextView!
    
    @IBOutlet weak var iconView: UIImageView!
    
    @IBOutlet weak var agoLabel: UILabel!
    
    
    @IBOutlet weak var noteView: MisskeyTextView!
    
    
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
    
    
    
    //MARK: Private Var
    private let disposeBag = DisposeBag()
    
    private var viewModel: ViewModel?
    
    
    private func getViewModel(item: NoteCell.Model, isDetailMode: Bool)-> ViewModel {
        let input: ViewModel.Input = .init(cellModel: item,
                                           isDetailMode: isDetailMode,
                                           noteYanagi: self.noteView,
                                           nameYanagi: self.nameTextView)
        
        
        let viewModel = NoteCellViewModel(with: input, and: self.disposeBag)
        
        self.binding(viewModel: viewModel)
        return viewModel
    }
    
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
        self.setupView()
    }
    
    private lazy var setupView: (()->()) = { //必ず一回しか読み込まれない
        self.setupSkeltonMode()
        self.setupProfileGesture() // プロフィールに飛ぶtapgestureを設定する
        self.setupFileView()
        return {}
    }()
    
    
    private func setupComponents() {
        //["FontAwesome5Free-Solid", "FontAwesome5Free-Regular"], ["FontAwesome5Brands-Regular"]
        
        self.iconView.layoutIfNeeded()
        
        self.iconView.layer.cornerRadius = self.iconView.frame.height / 2
        self.replyButton.titleLabel?.font = .awesomeSolid(fontSize: 15.0)
        self.renoteButton.titleLabel?.font = .awesomeSolid(fontSize: 15.0)
        self.reactionButton.titleLabel?.font = .awesomeSolid(fontSize: 15.0)
        self.othersButton.titleLabel?.font = .awesomeSolid(fontSize: 15.0)
        
        self.noteView.delegate = self
        self.noteView.xMargin = 0
        self.noteView.yMargin = 0
        
        
        if self.fileImageView.arrangedSubviews.count > 0 {
            self.fileImageContainer.translatesAutoresizingMaskIntoConstraints = false
        }
    }
    
    
    private func binding(viewModel: ViewModel) {
        let output = viewModel.output
        
        output.ago.drive(self.agoLabel.rx.text).disposed(by: disposeBag)
        output.name.drive(self.nameTextView.rx.attributedText).disposed(by: disposeBag)
        
        output.shapedNote.drive(self.noteView.rx.attributedText).disposed(by: disposeBag)
        output.iconImage.drive(self.iconView.rx.image).disposed(by: disposeBag)
        
        output.defaultConstraintActive.drive(self.displayName2MainStackConstraint.rx.active).disposed(by: disposeBag)
        output.defaultConstraintActive.drive(self.icon2MainStackConstraint.rx.active).disposed(by: disposeBag)
        
        output.backgroundColor.drive(self.rx.backgroundColor).disposed(by: disposeBag)
        
        output.isReplyTarget.drive(self.separatorBorder.rx.isHidden).disposed(by: disposeBag)
        output.isReplyTarget.map{!$0}.drive(self.replyIndicator.rx.isHidden).disposed(by: disposeBag)
    }
    
    private func setupProfileGesture() {
        let gestureTargets = [iconView, nameTextView]
        
        gestureTargets.forEach {
            guard let view = $0 else { return }
            view.setTapGesture(disposeBag) {
                guard let delegate = self.delegate, let userId = self.userId else { return }
                delegate.move2Profile(userId: userId)
            }
        }
    }
    
    private func changeStateFileImage(isHidden: Bool) {
        self.fileImageView.isHidden = isHidden
        self.fileImageContainer.isHidden = isHidden
    }
    
    //MARK: Public Methods
    public func initializeComponent(hasFile: Bool) {
        
        self.delegate = nil
        self.noteId = nil
        self.userId = nil
        
        self.backgroundColor = .white
        self.separatorBorder.isHidden = false
        self.replyIndicator.isHidden = true
        
        self.nameTextView.attributedText = nil
        self.iconView.image = nil
        self.agoLabel.text = nil
        self.noteView.attributedText = nil
        
        self.reactionsStackView.isHidden = false
        self.reactionsStackView.arrangedSubviews.forEach{ $0.removeFromSuperview() }
        self.reactionsStackView.subviews.forEach({ $0.removeFromSuperview() })
        
        self.fileImageView.arrangedSubviews.forEach{ $0.isHidden = true }
        
        //TODO: reactionを隠す時これつかう → UIView.animate(withDuration: 0.25, animations: { () -> Void in
        
        
        self.changeStateFileImage(isHidden: !hasFile)
        
        
        self.replyButton.setTitle("", for: .normal)
        self.renoteButton.setTitle("", for: .normal)
        self.reactionButton.setTitle("", for: .normal)
        
        //        self.nameTextView.resetViewString()
        //        self.noteView.resetViewString()
    }
    
    // ファイルは同時に4つしか載せることができないので、先に4つViewを追加しておく
    private func setupFileView() {
        for _ in 0 ..< 4 {
            let imageView = UIImageView()
            
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.isHidden = true
            imageView.layer.cornerRadius = 10
            imageView.isUserInteractionEnabled = true
            imageView.layer.borderColor = UIColor.lightGray.cgColor
            imageView.layer.borderWidth = 1
            imageView.layer.masksToBounds = true
            
            self.fileImageView.addArrangedSubview(imageView)
        }
    }
    
    public func setupFileImage(_ image: UIImage, originalImageUrl: String, index: Int) {
        //self.changeStateFileImage(isHidden: false) //メインスレッドでこれ実行するとStackViewの内部計算と順番が前後するのでダメ
        
        DispatchQueue.main.async {
            guard let imageView = self.getFileView(index) else { return }
            
            //tap gestureを付加する
            imageView.setTapGesture(self.disposeBag, closure: { self.showImage(url: originalImageUrl) })
            
            imageView.image = image
            imageView.isHidden = false
            
            self.imageView?.layoutIfNeeded()
            self.mainStackView.setNeedsLayout()
            
        }
    }
    
    private func getFileView(_ index: Int)-> UIImageView? {
        guard index < self.fileImageView.arrangedSubviews.count,
            let imageView = self.fileImageView.arrangedSubviews[index] as? UIImageView else { return nil }
        
        return imageView
    }
    
    private func showImage(url: String) {
        url.toUIImage{ image in
            guard let image = image, let delegate = self.delegate as? UIViewController else { return }
            
            DispatchQueue.main.async {
                let agrume = Agrume(image: image)
                agrume.show(from: delegate) // 画像を表示
            }
        }
    }
    
    
    public func shapeCell(item: NoteCell.Model, isDetailMode: Bool = false)-> NoteCell {
        guard !item.isSkelton else { //SkeltonViewを表示する
            self.changeSkeltonState(on: true)
            return self
        }
        
        //Font
        self.noteView.font = UIFont.init(name: "Helvetica",
                                         size: isDetailMode ? 15.0 : 11.0)
        self.nameTextView.font = UIFont.init(name: "Helvetica",
                                             size: 10.0)
        
        //余白消す
        self.nameTextView.textContainerInset = .zero
        self.nameTextView.textContainer.lineFragmentPadding = 0
        
        
        self.changeSkeltonState(on: false)
        
        guard let noteId = item.noteId else { return NoteCell() }
        
        self.initializeComponent(hasFile: item.files.count > 0) // Initialize because NoteCell is reused by TableView.
        
        //main
        self.noteId = item.noteId
        self.userId = item.userId
        
        self.noteView.setId(noteId: item.noteId)
        self.nameTextView.setId(userId: item.userId)
        
        let viewModel = getViewModel(item: item, isDetailMode: isDetailMode)
        viewModel.setCell()
        self.viewModel = viewModel
        
        self.iconImageUrl = viewModel.setImage(username: item.username, imageRawUrl: item.iconImageUrl)
        
        //file
        if let files = Cache.shared.getFiles(noteId: noteId) {
            for index in 0 ..< files.count {
                let file = files[index]
                self.setupFileImage(file.thumbnail, originalImageUrl: file.originalUrl, index: index)
            }
        }
        else {
            let files = item.files.filter{ $0 != nil }
            let fileCount = files.count
            
            for index in 0 ..< fileCount {
                let file = files[index]
                
                guard let thumbnailUrl = file!.thumbnailUrl,
                    let original = file!.url,
                    let imageView = self.getFileView(index) else { break }
                
                imageView.isHidden = false
                
                thumbnailUrl.toUIImage { image in
                    guard let image = image else { return }
                    
                    Cache.shared.saveFiles(noteId: noteId, image: image, originalUrl: original)
                    self.setupFileImage(image, originalImageUrl: original, index: index)
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
        
        return self
    }
    
    //MARK: Utilities
    private func setupSkeltonMode() {
        self.separatorBorder.isSkeletonable = true
        self.replyIndicator.isSkeletonable = true
        
        self.nameTextView.isSkeletonable = true
        self.iconView.isSkeletonable = true
        self.agoLabel.isSkeletonable = true
        self.noteView.isSkeletonable = true
        
        self.reactionsStackView.isSkeletonable = true
        
        self.fileImageView.isSkeletonable = true
    }
    
    
    private func changeSkeltonState(on: Bool) {
        if on {
            self.nameTextView.text = nil
            self.agoLabel.text = nil
            self.noteView.text = nil
            
            self.nameTextView.showAnimatedGradientSkeleton()
            self.iconView.showAnimatedGradientSkeleton()
            
            self.reactionsStackView.isHidden = true
            
            self.fileImageView.showAnimatedGradientSkeleton()
        }
        else {
            self.nameTextView.hideSkeleton()
            self.iconView.hideSkeleton()
            
            self.reactionsStackView.isHidden = false
            
            
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
        guard let viewModel = viewModel else { return }
        
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
        guard let delegate = delegate, let noteId = self.noteId, let viewModel = viewModel else { return }
        
        delegate.tappedReaction(noteId: noteId,
                                iconUrl: self.iconImageUrl,
                                displayName: viewModel.output.displayName,
                                username: viewModel.output.username,
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
        
        var isSkelton = false
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
        
        static func fakeSkeltonCell()-> NoteCell.Model {
            
            return NoteCell.Model(isSkelton: true,
                                  isRenoteeCell: false,
                                  renotee: "",
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
