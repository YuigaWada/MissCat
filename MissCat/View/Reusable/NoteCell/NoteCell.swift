//
//  Note.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/12.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Agrume
import MisskeyKit
import RxCocoa
import RxDataSources
import RxSwift
import SkeletonView
import UIKit
import WebKit

public protocol NoteCellDelegate {
    func tappedReply()
    func tappedRenote(noteId: String)
    func tappedReaction(noteId: String, iconUrl: String?, displayName: String, username: String, note: NSAttributedString, hasFile: Bool, hasMarked: Bool)
    func tappedOthers()
    
    func move2PostDetail(item: NoteCell.Model)
    
    func vote(choice: Int, to noteId: String)
    
    func tappedLink(text: String)
    func move2Profile(userId: String)
    
    func playVideo(url: String)
}

private typealias ViewModel = NoteCellViewModel
typealias ReactionsDataSource = RxCollectionViewSectionedReloadDataSource<NoteCell.Reaction.Section>

public class NoteCell: UITableViewCell, UITextViewDelegate, ReactionCellDelegate, UICollectionViewDelegate, ComponentType {
    public struct Arg {
        var item: NoteCell.Model
        var isDetailMode: Bool = false
    }
    
    public typealias Transformed = NoteCell
    
    // MARK: IBOutlet (UIView)
    
    @IBOutlet weak var nameTextView: MisskeyTextView!
    
    @IBOutlet weak var iconView: UIImageView!
    
    @IBOutlet weak var agoLabel: UILabel!
    
    @IBOutlet weak var noteView: MisskeyTextView!
    
    @IBOutlet weak var fileImageView: UIStackView!
    @IBOutlet weak var fileImageContainer: UIView!
    
    @IBOutlet weak var reactionsCollectionView: UICollectionView!
    
    @IBOutlet weak var pollView: PollView!
    
    @IBOutlet weak var innerRenoteDisplay: UIView!
    
    @IBOutlet weak var actionStackView: UIStackView!
    @IBOutlet weak var replyButton: UIButton!
    @IBOutlet weak var renoteButton: UIButton!
    @IBOutlet weak var reactionButton: UIButton!
    @IBOutlet weak var othersButton: UIButton!
    
    @IBOutlet weak var separatorBorder: UIView!
    @IBOutlet weak var replyIndicator: UIView!
    
    @IBOutlet weak var mainStackView: UIStackView!
    
    // MARK: IBOutlet (Constraint)
    
    @IBOutlet weak var displayName2MainStackConstraint: NSLayoutConstraint!
    @IBOutlet weak var icon2MainStackConstraint: NSLayoutConstraint!
    @IBOutlet weak var reactionCollectionHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var pollViewHeightConstraint: NSLayoutConstraint!
    
    // MARK: Public Var
    
    public var delegate: NoteCellDelegate? {
        didSet {
            guard let commentRenoteView = commentRenoteView else { return }
            commentRenoteView.delegate = delegate
        }
    }
    
    public var noteId: String?
    public var userId: String?
    public var iconImageUrl: String?
    
    // MARK: Private Var
    
    private let disposeBag = DisposeBag()
    private lazy var reactionsDataSource = self.setupDataSource()
    private var viewModel: ViewModel?
    private var commentRenoteView: NoteCell?
    private var onOtherNote: Bool = false
    
    private func getViewModel(item: NoteCell.Model, isDetailMode: Bool) -> ViewModel {
        let input: ViewModel.Input = .init(cellModel: item,
                                           isDetailMode: isDetailMode,
                                           noteYanagi: noteView,
                                           nameYanagi: nameTextView)
        
        let viewModel = NoteCellViewModel(with: input, and: disposeBag)
        
        binding(viewModel: viewModel, noteId: item.noteId ?? "")
        setCommentRenoteCell()
        return viewModel
    }
    
    // MARK: Life Cycle
    
    public override func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority, verticalFittingPriority: UILayoutPriority) -> CGSize {
        contentView.bounds.size = targetSize
        contentView.layoutIfNeeded()
        return super.systemLayoutSizeFitting(targetSize,
                                             withHorizontalFittingPriority: horizontalFittingPriority,
                                             verticalFittingPriority: verticalFittingPriority)
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        setupView()
        setupComponents()
        
        nameTextView.transformText() // TODO: せっかくisHiddenがどうこうやってたのが反映されていないような気がする
        noteView.transformText()
    }
    
    private lazy var setupView: (() -> Void) = { // 必ず一回しか読み込まれない
        self.setupSkeltonMode()
        self.setupProfileGesture() // プロフィールに飛ぶtapgestureを設定する
        self.setupCollectionView()
        return {}
    }()
    
    private func setupCollectionView() {
        reactionsCollectionView.backgroundColor = .clear
        
        let flowLayout = UICollectionViewFlowLayout()
        let width = mainStackView.frame.width / 6
        
        flowLayout.itemSize = CGSize(width: width, height: 30)
        //        flowLayout.scrollDirection = .horizontal
        flowLayout.minimumInteritemSpacing = 5
        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        reactionsCollectionView.collectionViewLayout = flowLayout
    }
    
    private func setupDataSource() -> ReactionsDataSource {
        reactionsCollectionView.register(UINib(nibName: "ReactionCell", bundle: nil), forCellWithReuseIdentifier: "ReactionCell")
        reactionsCollectionView.rx.setDelegate(self).disposed(by: disposeBag)
        
        let dataSource = ReactionsDataSource(
            configureCell: { dataSource, collectionView, indexPath, _ in
                self.setupReactionCell(dataSource, collectionView, indexPath)
            }
        )
        
        return dataSource
    }
    
    private func setupComponents() {
        // ["FontAwesome5Free-Solid", "FontAwesome5Free-Regular"], ["FontAwesome5Brands-Regular"]
        
        iconView.layoutIfNeeded()
        
        iconView.layer.cornerRadius = iconView.frame.height / 2
        replyButton.titleLabel?.font = .awesomeSolid(fontSize: 15.0)
        renoteButton.titleLabel?.font = .awesomeSolid(fontSize: 15.0)
        reactionButton.titleLabel?.font = .awesomeSolid(fontSize: 15.0)
        othersButton.titleLabel?.font = .awesomeSolid(fontSize: 15.0)
        
        noteView.delegate = self
        
        noteView.isUserInteractionEnabled = true
        
        if fileImageView.arrangedSubviews.count > 0 {
            fileImageContainer.translatesAutoresizingMaskIntoConstraints = false
        }
    }
    
    private func binding(viewModel: ViewModel, noteId: String) {
        let output = viewModel.output
        
        // reaction
        output.reactions.asDriver(onErrorDriveWith: Driver.empty()).drive(reactionsCollectionView.rx.items(dataSource: reactionsDataSource)).disposed(by: disposeBag)
        output.reactions.asDriver(onErrorDriveWith: Driver.empty()).map { // リアクションの数が0のときはreactionsCollectionViewを非表示に
            guard $0.count == 1 else { return true }
            return $0[0].items.count == 0
        }.drive(reactionsCollectionView.rx.isHidden).disposed(by: disposeBag)
        
        output.reactions.asDriver(onErrorDriveWith: Driver.empty()).map { // リアクションの数によってreactionsCollectionViewの高さを調節
            guard $0.count == 1 else { return 30 }
            let count = $0[0].items.count
            let step = ceil(Double(count) / 5)
            
            return CGFloat(step * 40)
        }.drive(reactionCollectionHeightConstraint.rx.constant).disposed(by: disposeBag)
        
        // Renote With Comment
        
        output.commentRenoteTarget.asDriver(onErrorDriveWith: Driver.empty()).drive(onNext: { renoteModel in
            self.commentRenoteView = self.commentRenoteView?.transform(with: .init(item: renoteModel)) // MEMO: やっぱりここが重いっぽい
            self.commentRenoteView?.setTapGesture(self.disposeBag, closure: {
                guard let noteId = renoteModel.noteId else { return }
                self.delegate?.move2PostDetail(item: renoteModel)
            })
        }).disposed(by: disposeBag)
        
        output.commentRenoteTarget.asDriver(onErrorDriveWith: Driver.empty()).map { _ in false }.drive(innerRenoteDisplay.rx.isHidden).disposed(by: disposeBag)
        
        output.onOtherNote.asDriver(onErrorDriveWith: Driver.empty()).drive(actionStackView.rx.isHidden).disposed(by: disposeBag)
        output.onOtherNote.asDriver(onErrorDriveWith: Driver.empty()).drive(reactionsCollectionView.rx.isHidden).disposed(by: disposeBag)
        
        // poll
        output.poll.asDriver(onErrorDriveWith: Driver.empty()).drive(onNext: { poll in
            self.pollView.isHidden = false
            self.pollView.setPoll(with: poll)
            self.pollViewHeightConstraint.constant = self.pollView.height
            
            self.pollView.voteTriggar?.asDriver(onErrorDriveWith: Driver.empty()).drive(onNext: { id in
                self.delegate?.vote(choice: id, to: noteId)
            }).disposed(by: self.disposeBag)
        }).disposed(by: disposeBag)
        
        // general
        output.ago.asDriver(onErrorDriveWith: Driver.empty()).drive(agoLabel.rx.text).disposed(by: disposeBag)
        output.name.asDriver(onErrorDriveWith: Driver.empty()).drive(nameTextView.rx.attributedText).disposed(by: disposeBag)
        
//        output.name.asDriver(onErrorDriveWith: Driver.empty()).drive(onNext: { _ in
//            self.nameTextView.showMFM()
//        }).disposed(by: disposeBag)
        
        output.shapedNote.asDriver(onErrorDriveWith: Driver.empty()).drive(noteView.rx.attributedText).disposed(by: disposeBag)
        output.shapedNote.asDriver(onErrorDriveWith: Driver.empty()).map { $0 == nil }.drive(noteView.rx.isHidden).disposed(by: disposeBag) // 画像onlyや投票onlyの場合、noteが存在しない場合がある→ noteViewを非表示にする
        
        output.iconImage.asDriver(onErrorDriveWith: Driver.empty()).drive(iconView.rx.image).disposed(by: disposeBag)
        
        // constraint
        output.defaultConstraintActive.asDriver(onErrorDriveWith: Driver.empty()).drive(displayName2MainStackConstraint.rx.active).disposed(by: disposeBag)
        output.defaultConstraintActive.asDriver(onErrorDriveWith: Driver.empty()).drive(icon2MainStackConstraint.rx.active).disposed(by: disposeBag)
        
        // color
        output.backgroundColor.asDriver(onErrorDriveWith: Driver.empty()).drive(rx.backgroundColor).disposed(by: disposeBag)
        
        // hidden
        output.isReplyTarget.asDriver(onErrorDriveWith: Driver.empty()).drive(separatorBorder.rx.isHidden).disposed(by: disposeBag)
        output.isReplyTarget.map { !$0 }.asDriver(onErrorDriveWith: Driver.empty()).drive(replyIndicator.rx.isHidden).disposed(by: disposeBag)
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
        fileImageView.isHidden = isHidden
        fileImageContainer.isHidden = isHidden
    }
    
    // MARK: Public Methods
    
    public func transform(with arg: Arg) -> NoteCell {
        let item = arg.item
        let isDetailMode = arg.isDetailMode
        guard !item.isSkelton else { // SkeltonViewを表示する
            changeSkeltonState(on: true)
            return self
        }
        
        // Font
        noteView.font = UIFont(name: "Helvetica",
                               size: isDetailMode ? 15.0 : 11.0)
        nameTextView.font = UIFont(name: "Helvetica",
                                   size: 10.0)
        
        nameTextView.xMargin = 0
        nameTextView.yMargin = 0
        
        noteView.xMargin = 0
        noteView.yMargin = 0
        
        reactionsCollectionView.isHidden = true // リアクションが存在しない場合はHideする
        
        // 余白消す
        nameTextView.textContainerInset = .zero
        nameTextView.textContainer.lineFragmentPadding = 0
        
        changeSkeltonState(on: false)
        
        guard let noteId = item.noteId else { return NoteCell() }
        
        initializeComponent(hasFile: item.files.count > 0) // Initialize because NoteCell is reused by TableView.
        
        // main
        self.noteId = item.noteId
        userId = item.userId
        iconImageUrl = item.iconImageUrl
        
        // YanagiTextと一対一にキャッシュを保存できるように、idをYanagiTextに渡す
        noteView.setId(noteId: item.noteId)
        nameTextView.setId(userId: item.userId)
        
        let viewModel = getViewModel(item: item, isDetailMode: isDetailMode)
        self.viewModel = viewModel
        
        viewModel.setCell()
        
        // file
        if let files = Cache.shared.getFiles(noteId: noteId) { // キャッシュが存在する場合
            for index in 0 ..< files.count {
                let file = files[index]
                setupFileImage(file.thumbnail,
                               originalUrl: file.originalUrl,
                               index: index,
                               isVideo: file.type == .Video,
                               isSensitive: file.isSensitive)
            }
        } else { // キャッシュが存在しない場合
            let files = item.files
            let fileCount = files.count
            
            for index in 0 ..< fileCount {
                let file = files[index]
                let fileType = viewModel.checkFileType(file.type)
                
                guard fileType != .Unknown,
                    let thumbnailUrl = file.thumbnailUrl,
                    let original = file.url,
                    let imageView = getFileView(index) else { break }
                
                imageView.isHidden = false
                
                if fileType == .Audio {
                } else {
                    thumbnailUrl.toUIImage { image in
                        guard let image = image else { return }
                        
                        Cache.shared.saveFiles(noteId: noteId,
                                               image: image,
                                               originalUrl: original,
                                               type: fileType,
                                               isSensitive: file.isSensitive ?? false)
                        
                        self.setupFileImage(image,
                                            originalUrl: original,
                                            index: index,
                                            isVideo: fileType == .Video,
                                            isSensitive: file.isSensitive ?? true)
                    }
                }
            }
        }
        
        // footer
        let replyCount = item.replyCount != 0 ? String(item.replyCount) : ""
        let renoteCount = item.renoteCount != 0 ? String(item.renoteCount) : ""
        var reactionsCount: Int = 0
        item.reactions.forEach {
            reactionsCount += Int($0.count ?? "0") ?? 0
        }
        
        replyButton.setTitle("reply\(replyCount)", for: .normal)
        renoteButton.setTitle("retweet\(renoteCount)", for: .normal)
        reactionButton.setTitle("plus\(reactionsCount == 0 ? "" : String(reactionsCount))", for: .normal)
        
        // reaction
        
        return self
    }
    
    func initializeComponent(hasFile: Bool) {
        delegate = nil
        noteId = nil
        userId = nil
        
        backgroundColor = .white
        separatorBorder.isHidden = false
        replyIndicator.isHidden = true
        
        nameTextView.attributedText = nil
        nameTextView.resetViewString()
        
        iconView.image = nil
        agoLabel.text = nil
        noteView.attributedText = nil
        noteView.isHidden = false
        noteView.resetViewString()
        
        setupFileView()
        fileImageView.arrangedSubviews.forEach {
            guard let imageView = $0 as? UIImageView else { return }
            imageView.isHidden = true
            imageView.image = nil
        }
        
        changeStateFileImage(isHidden: !hasFile)
        
        replyButton.setTitle("", for: .normal)
        renoteButton.setTitle("", for: .normal)
        reactionButton.setTitle("", for: .normal)
        
        pollView.isHidden = true
        pollView.initialize()
        
        innerRenoteDisplay.isHidden = true
    }
    
    // MARK: Privates
    
    private func setupFileImage(_ image: UIImage, originalUrl: String, index: Int, isVideo: Bool, isSensitive: Bool) {
        // self.changeStateFileImage(isHidden: false) //メインスレッドでこれ実行するとStackViewの内部計算と順番が前後するのでダメ
        
        DispatchQueue.main.async {
            guard let imageView = self.getFileView(index) else { return }
            
            // tap gestureを付加する
            imageView.setTapGesture(self.disposeBag, closure: {
                if isVideo {
                    self.delegate?.playVideo(url: originalUrl)
                } else {
                    self.showImage(url: originalUrl)
                }
            })
            
            imageView.backgroundColor = .clear
            imageView.image = image
            imageView.isHidden = false
            imageView.setPlayIconImage(hide: !isVideo)
            imageView.setNSFW(hide: !isSensitive)
            
            imageView.layoutIfNeeded()
            self.mainStackView.setNeedsLayout()
        }
    }
    
    // ファイルは同時に4つしか載せることができないので、先に4つViewを追加しておく
    private func setupFileView() {
        guard fileImageView.arrangedSubviews.count == 0 else { return }
        
        for _ in 0 ..< 4 {
            let imageView = FileView()
            
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.isHidden = true
            imageView.layer.cornerRadius = 10
            imageView.isUserInteractionEnabled = true
            imageView.backgroundColor = .lightGray
            imageView.layer.borderColor = UIColor.lightGray.cgColor
            imageView.layer.borderWidth = 1
            imageView.layer.masksToBounds = true
            
            fileImageView.addArrangedSubview(imageView)
        }
    }
    
    private func getFileView(_ index: Int) -> FileView? {
        guard index < fileImageView.arrangedSubviews.count,
            let imageView = fileImageView.arrangedSubviews[index] as? FileView else { return nil }
        
        return imageView
    }
    
    private func showImage(url: String) {
        guard let url = URL(string: url), let delegate = self.delegate as? UIViewController else { return }
        
        let agrume = Agrume(url: url)
        agrume.show(from: delegate) // 画像を表示
    }
    
    private func setupReactionCell(_ dataSource: CollectionViewSectionedDataSource<NoteCell.Reaction.Section>, _ collectionView: UICollectionView, _ indexPath: IndexPath) -> UICollectionViewCell {
        guard let viewModel = viewModel else { fatalError("Internal Error.") }
        
        let index = indexPath.row
        let reactionsModel = viewModel.reactionsModel
        
        guard let cell = reactionsCollectionView.dequeueReusableCell(withReuseIdentifier: "ReactionCell", for: indexPath) as? ReactionCell else { fatalError("Internal Error.") }
        
        if index < reactionsModel.count {
            let item = reactionsModel[index]
            
            let shapedCell = viewModel.setReactionCell(with: item, to: cell)
            shapedCell.delegate = self
            
            return shapedCell
        }
        
        return cell
    }
    
    // MARK: 引用RN
    
    private func setCommentRenoteCell() { // 引用RN
        guard !onOtherNote,
            commentRenoteView == nil,
            let commentRenoteView = UINib(nibName: "NoteCell", bundle: nil).instantiate(withOwner: self, options: nil).first as? NoteCell else { return }
        
        // NibからNoteCellを生成し、parentViewに対してAutoLayoutを設定 + 枠線を設定
        innerRenoteDisplay.layer.borderWidth = 1
        innerRenoteDisplay.layer.borderColor = UIColor.systemBlue.cgColor
        innerRenoteDisplay.layer.cornerRadius = 5
        
        commentRenoteView.onOtherNote = true
        commentRenoteView.translatesAutoresizingMaskIntoConstraints = false
        innerRenoteDisplay.addSubview(commentRenoteView)
        
        if let innerRenoteDisplay = innerRenoteDisplay {
            innerRenoteDisplay.addConstraints([
                NSLayoutConstraint(item: innerRenoteDisplay,
                                   attribute: .top,
                                   relatedBy: .equal,
                                   toItem: commentRenoteView,
                                   attribute: .top,
                                   multiplier: 1.0,
                                   constant: 0),
                
                NSLayoutConstraint(item: innerRenoteDisplay,
                                   attribute: .bottom,
                                   relatedBy: .equal,
                                   toItem: commentRenoteView,
                                   attribute: .bottom,
                                   multiplier: 1.0,
                                   constant: 0),
                
                NSLayoutConstraint(item: innerRenoteDisplay,
                                   attribute: .right,
                                   relatedBy: .equal,
                                   toItem: commentRenoteView,
                                   attribute: .right,
                                   multiplier: 1.0,
                                   constant: 0),
                
                NSLayoutConstraint(item: innerRenoteDisplay,
                                   attribute: .left,
                                   relatedBy: .equal,
                                   toItem: commentRenoteView,
                                   attribute: .left,
                                   multiplier: 1.0,
                                   constant: 0)
            ])
        }
        
        self.commentRenoteView = commentRenoteView
    }
    
    // MARK: Skelton
    
    private func setupSkeltonMode() {
        separatorBorder.isSkeletonable = true
        replyIndicator.isSkeletonable = true
        
        nameTextView.isSkeletonable = true
        iconView.isSkeletonable = true
        agoLabel.isSkeletonable = true
        noteView.isSkeletonable = true
        
        reactionsCollectionView.isSkeletonable = true
        
        fileImageView.isSkeletonable = true
    }
    
    private func changeSkeltonState(on: Bool) {
        if on {
            nameTextView.text = nil
            agoLabel.text = nil
            noteView.text = nil
            
            nameTextView.showAnimatedGradientSkeleton()
            iconView.showAnimatedGradientSkeleton()
            
            reactionsCollectionView.isHidden = true
            pollView.isHidden = true
            innerRenoteDisplay.isHidden = true
            
            fileImageView.showAnimatedGradientSkeleton()
        } else {
            nameTextView.hideSkeleton()
            iconView.hideSkeleton()
            
            fileImageView.hideSkeleton()
        }
    }
    
    // MARK: DELEGATE
    
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
        } else {
            viewModel.cancelReaction(noteId: noteId)
        }
    }
    
    // MARK: IBAction
    
    @IBAction func tappedReply(_ sender: Any) {
        guard let delegate = delegate else { return }
        delegate.tappedReply()
    }
    
    @IBAction func tappedRenote(_ sender: Any) {
        guard let delegate = delegate, let noteId = noteId else { return }
        delegate.tappedRenote(noteId: noteId)
    }
    
    @IBAction func tappedReaction(_ sender: Any) {
        guard let delegate = delegate, let noteId = self.noteId, let viewModel = viewModel else { return }
        
        delegate.tappedReaction(noteId: noteId,
                                iconUrl: iconImageUrl,
                                displayName: viewModel.output.displayName,
                                username: viewModel.output.username,
                                note: noteView.attributedText,
                                hasFile: false,
                                hasMarked: false)
    }
    
    @IBAction func tappedOthers(_ sender: Any) {
        guard let delegate = delegate else { return }
        delegate.tappedOthers()
    }
}

// MARK: NoteCell.Model

extension NoteCell {
    public class Model: IdentifiableType, Equatable {
        var isSkelton = false
        var isReactionGenCell = false
        var isRenoteeCell = false
        var renotee: String?
        var baseNoteId: String? // どのcellに対するReactionGenCellなのか
        var isReply: Bool = false // リプライであるかどうか
        var isReplyTarget: Bool = false // リプライ先の投稿であるかどうか
        
        public let identity: String = String(Float.random(in: 1 ..< 100))
        let noteId: String?
        
        public typealias Identity = String
        
        let iconImageUrl: String?
        var iconImage: UIImage?
        
        let userId: String
        
        let displayName: String
        var shapedDisplayName: MFMString?
        
        let username: String
        
        let note: String
        var shapedNote: MFMString?
        
        let ago: String
        let replyCount: Int
        let renoteCount: Int
        var reactions: [ReactionCount]
        var shapedReactions: [NoteCell.Reaction]
        var myReaction: String?
        let files: [File]
        let emojis: [EmojiModel]?
        
        let commentRNTarget: NoteCell.Model?
        
        var onOtherNote: Bool = false // 引用RNはNoteCellの上にNoteCellが乗るという二重構造になっているので、内部のNoteCellかどうかを判別する
        var poll: Poll?
        
        init(isSkelton: Bool = false, isReactionGenCell: Bool = false, isRenoteeCell: Bool = false, renotee: String? = nil, baseNoteId: String? = nil, isReply: Bool = false, isReplyTarget: Bool = false, noteId: String? = nil, iconImageUrl: String? = nil, iconImage: UIImage? = nil, userId: String, displayName: String, username: String, note: String, ago: String, replyCount: Int, renoteCount: Int, reactions: [ReactionCount], shapedReactions: [NoteCell.Reaction], myReaction: String? = nil, files: [File], emojis: [EmojiModel]? = nil, commentRNTarget: NoteCell.Model? = nil, onOtherNote: Bool = false, poll: Poll? = nil) {
            self.isSkelton = isSkelton
            self.isReactionGenCell = isReactionGenCell
            self.isRenoteeCell = isRenoteeCell
            self.renotee = renotee
            self.baseNoteId = baseNoteId
            self.isReply = isReply
            self.isReplyTarget = isReplyTarget
            self.noteId = noteId
            self.iconImageUrl = iconImageUrl
            self.iconImage = iconImage
            self.userId = userId
            self.displayName = displayName
            self.username = username
            self.note = note
            self.ago = ago
            self.replyCount = replyCount
            self.renoteCount = renoteCount
            self.reactions = reactions
            self.shapedReactions = shapedReactions
            self.myReaction = myReaction
            self.files = files
            self.emojis = emojis
            self.commentRNTarget = commentRNTarget
            self.onOtherNote = onOtherNote
            self.poll = poll
        }
        
        public static func == (lhs: NoteCell.Model, rhs: NoteCell.Model) -> Bool {
            return lhs.identity == rhs.identity
        }
        
        // MARK: Statics
        
        static func fakeRenoteecell(renotee: String, baseNoteId: String) -> NoteCell.Model {
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
                                  shapedReactions: [],
                                  myReaction: nil,
                                  files: [],
                                  emojis: [],
                                  commentRNTarget: nil,
                                  poll: nil)
        }
        
        static func fakeSkeltonCell() -> NoteCell.Model {
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
                                  shapedReactions: [],
                                  myReaction: nil,
                                  files: [],
                                  emojis: [],
                                  commentRNTarget: nil,
                                  poll: nil)
        }
    }
    
    struct Section {
        var items: [Model]
    }
    
    struct Reaction: IdentifiableType, Equatable {
        typealias Identity = String
        var identity: String
        var noteId: String
        
        var url: String?
        var rawEmoji: String?
        
        var isMyReaction: Bool
        
        var count: String
        
        struct Section {
            var items: [Reaction]
        }
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

extension NoteCell.Reaction.Section: AnimatableSectionModelType {
    typealias Item = NoteCell.Reaction
    typealias Identity = String
    
    public var identity: String {
        return ""
    }
    
    init(original: Item.Section, items: [Item]) {
        self = original
        self.items = items
    }
}

extension NoteCell.Model {
    /// ReactionCountをNoteCell.Reactionに変換する
    func getReactions() -> [NoteCell.Reaction] {
        return reactions.map { reaction in
            guard let count = reaction.count, count != "0" else { return nil }
            
            let rawEmoji = reaction.name ?? ""
            let isMyReaction = rawEmoji == self.myReaction
            
            guard rawEmoji != "", let convertedEmojiData = EmojiHandler.handler.convertEmoji(raw: rawEmoji) else {
                // If being not converted
                let reactionModel = NoteCell.Reaction(identity: UUID().uuidString,
                                                      noteId: self.noteId ?? "",
                                                      url: nil,
                                                      rawEmoji: rawEmoji,
                                                      isMyReaction: isMyReaction,
                                                      count: count)
                return reactionModel
            }
            
            var reactionModel: NoteCell.Reaction
            switch convertedEmojiData.type {
            case "default":
                reactionModel = NoteCell.Reaction(identity: UUID().uuidString,
                                                  noteId: self.noteId ?? "",
                                                  url: nil,
                                                  rawEmoji: convertedEmojiData.emoji,
                                                  isMyReaction: isMyReaction,
                                                  count: count)
            case "custom":
                reactionModel = NoteCell.Reaction(identity: UUID().uuidString,
                                                  noteId: self.noteId ?? "",
                                                  url: convertedEmojiData.emoji,
                                                  rawEmoji: convertedEmojiData.emoji,
                                                  isMyReaction: isMyReaction,
                                                  count: count)
            default:
                return nil
            }
            
            return reactionModel
        }.compactMap { $0 } // nil除去
    }
}

extension NoteCell {
    public enum FileType {
        case PlaneImage
        case GIFImage
        case Video
        case Audio
        case Unknown
    }
    
    public class FileView: UIImageView {
        private var playIconImageView: UIImageView?
        private var nsfwCover: UIView?
        
        public func setPlayIconImage(hide: Bool = false) {
            let parentView = self
            guard playIconImageView == nil, !hide else {
                playIconImageView?.isHidden = hide; return
            }
            
            guard let playIconImage = UIImage(named: "play") else { return }
            let playIconImageView = UIImageView(image: playIconImage)
            
            let edgeMultiplier: CGFloat = 0.4
            
            parentView.layoutIfNeeded()
            let parentFrame = parentView.frame
            let edge = min(parentFrame.width, parentFrame.height) * edgeMultiplier
            
            playIconImageView.center = parentView.center
            playIconImageView.frame = CGRect(x: playIconImageView.frame.origin.x,
                                             y: playIconImageView.frame.origin.y,
                                             width: edge,
                                             height: edge)
            
            playIconImageView.translatesAutoresizingMaskIntoConstraints = false
            parentView.addSubview(playIconImageView)
            
            parentView.addConstraints([
                NSLayoutConstraint(item: playIconImageView,
                                   attribute: .width,
                                   relatedBy: .equal,
                                   toItem: parentView,
                                   attribute: .width,
                                   multiplier: 0,
                                   constant: edge),
                
                NSLayoutConstraint(item: playIconImageView,
                                   attribute: .height,
                                   relatedBy: .equal,
                                   toItem: parentView,
                                   attribute: .height,
                                   multiplier: 0,
                                   constant: edge),
                
                NSLayoutConstraint(item: playIconImageView,
                                   attribute: .centerX,
                                   relatedBy: .equal,
                                   toItem: parentView,
                                   attribute: .centerX,
                                   multiplier: 1.0,
                                   constant: 0),
                
                NSLayoutConstraint(item: playIconImageView,
                                   attribute: .centerY,
                                   relatedBy: .equal,
                                   toItem: parentView,
                                   attribute: .centerY,
                                   multiplier: 1.0,
                                   constant: 0)
            ])
            
            self.playIconImageView = playIconImageView
        }
        
        public func setNSFW(hide: Bool = false) {
            guard nsfwCover == nil, !hide else {
                nsfwCover?.isHidden = hide; return
            }
            
            let parentView = self
            parentView.layoutIfNeeded()
            
            // coverView
            let coverView = UIView()
            let parentFrame = parentView.frame
            coverView.backgroundColor = .clear
            coverView.frame = parentFrame
            coverView.translatesAutoresizingMaskIntoConstraints = false
            parentView.addSubview(coverView)
            
            // すりガラス
            let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
            blurView.translatesAutoresizingMaskIntoConstraints = false
            coverView.addSubview(blurView)
            
            // label: 閲覧注意 タップで表示
            let nsfwLabel = UILabel()
            nsfwLabel.text = "閲覧注意\nタップで表示"
            nsfwLabel.center = parentView.center
            nsfwLabel.textAlignment = .center
            nsfwLabel.numberOfLines = 2
            nsfwLabel.textColor = .init(hex: "FFFF8F")
            
            nsfwLabel.translatesAutoresizingMaskIntoConstraints = false
            coverView.addSubview(nsfwLabel)
            
            // AutoLayout
            parentView.addConstraints([
                NSLayoutConstraint(item: coverView,
                                   attribute: .width,
                                   relatedBy: .equal,
                                   toItem: parentView,
                                   attribute: .width,
                                   multiplier: 1.0,
                                   constant: 0),
                
                NSLayoutConstraint(item: coverView,
                                   attribute: .height,
                                   relatedBy: .equal,
                                   toItem: parentView,
                                   attribute: .height,
                                   multiplier: 1.0,
                                   constant: 0),
                
                NSLayoutConstraint(item: coverView,
                                   attribute: .centerX,
                                   relatedBy: .equal,
                                   toItem: parentView,
                                   attribute: .centerX,
                                   multiplier: 1.0,
                                   constant: 0),
                
                NSLayoutConstraint(item: coverView,
                                   attribute: .centerY,
                                   relatedBy: .equal,
                                   toItem: parentView,
                                   attribute: .centerY,
                                   multiplier: 1.0,
                                   constant: 0)
            ])
            
            coverView.addConstraints([
                NSLayoutConstraint(item: blurView,
                                   attribute: .width,
                                   relatedBy: .equal,
                                   toItem: coverView,
                                   attribute: .width,
                                   multiplier: 1.0,
                                   constant: 0),
                
                NSLayoutConstraint(item: blurView,
                                   attribute: .height,
                                   relatedBy: .equal,
                                   toItem: coverView,
                                   attribute: .height,
                                   multiplier: 1.0,
                                   constant: 0),
                
                NSLayoutConstraint(item: blurView,
                                   attribute: .centerX,
                                   relatedBy: .equal,
                                   toItem: coverView,
                                   attribute: .centerX,
                                   multiplier: 1.0,
                                   constant: 0),
                
                NSLayoutConstraint(item: blurView,
                                   attribute: .centerY,
                                   relatedBy: .equal,
                                   toItem: coverView,
                                   attribute: .centerY,
                                   multiplier: 1.0,
                                   constant: 0)
            ])
            
            parentView.addConstraints([
                NSLayoutConstraint(item: nsfwLabel,
                                   attribute: .centerX,
                                   relatedBy: .equal,
                                   toItem: parentView,
                                   attribute: .centerX,
                                   multiplier: 1.0,
                                   constant: 0),
                
                NSLayoutConstraint(item: nsfwLabel,
                                   attribute: .centerY,
                                   relatedBy: .equal,
                                   toItem: parentView,
                                   attribute: .centerY,
                                   multiplier: 1.0,
                                   constant: 0)
            ])
            
            nsfwCover = coverView
        }
    }
}
