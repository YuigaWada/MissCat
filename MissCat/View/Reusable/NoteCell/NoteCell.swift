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
    func tappedReply(note: NoteCell.Model)
    func tappedRenote(note: NoteCell.Model)
    func tappedReaction(noteId: String, iconUrl: String?, displayName: String, username: String, note: NSAttributedString, hasFile: Bool, hasMarked: Bool)
    func tappedOthers()
    
    func move2PostDetail(item: NoteCell.Model)
    
    func updateMyReaction(targetNoteId: String, rawReaction: String, plus: Bool)
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
        var delegate: NoteCellDelegate?
    }
    
    public typealias Transformed = NoteCell
    
    // MARK: IBOutlet (UIView)
    
    @IBOutlet weak var nameTextView: MisskeyTextView!
    
    @IBOutlet weak var iconView: UIImageView!
    
    @IBOutlet weak var agoLabel: UILabel!
    
    @IBOutlet weak var noteView: MisskeyTextView!
    
    @IBOutlet weak var reactionsCollectionView: UICollectionView!
    
    @IBOutlet weak var skeltonCover: UIView!
    @IBOutlet weak var fileContainer: FileContainer!
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
    
    @IBOutlet weak var nameHeightConstraint: NSLayoutConstraint!
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
    
    private var noteModel: NoteCell.Model?
    private var commentRenoteView: NoteCell?
    private var onOtherNote: Bool = false
    private var isSkelton: Bool = false
    
    private func getViewModel(item: NoteCell.Model, isDetailMode: Bool) -> ViewModel {
        let input: ViewModel.Input = .init(cellModel: item,
                                           isDetailMode: isDetailMode,
                                           noteYanagi: noteView,
                                           nameYanagi: nameTextView)
        
        let viewModel = NoteCellViewModel(with: input, and: disposeBag)
        
        noteModel = item
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
        
        if onOtherNote {
            nameTextView.renderViewStrings()
            noteView.renderViewStrings()
        }
        
        if isSkelton {
            // 以下２行を書くとskeltonViewが正常に表示される
            layoutIfNeeded()
            skeltonCover.updateAnimatedGradientSkeleton()
        }
    }
    
    private lazy var setupView: (() -> Void) = { // 必ず一回しか読み込まれない
        self.setupProfileGesture() // プロフィールに飛ぶtapgestureを設定する
        self.setupCollectionView()
        self.themeBinding()
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
        
        fileContainer.clipsToBounds = true
        fileContainer.layer.cornerRadius = 10
        fileContainer.layer.borderColor = UIColor.lightGray.cgColor
        fileContainer.layer.borderWidth = 1
        
        skeltonCover.isUserInteractionEnabled = false
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
            self.commentRenoteView = self.commentRenoteView?.transform(with: .init(item: renoteModel, delegate: self.delegate)) // MEMO: やっぱりここが重いっぽい
            self.commentRenoteView?.setTapGesture(self.disposeBag, closure: {
                guard let noteId = renoteModel.noteId else { return }
                self.delegate?.move2PostDetail(item: renoteModel)
            })
        }).disposed(by: disposeBag)
        
        output.commentRenoteTarget.asDriver(onErrorDriveWith: Driver.empty()).map { _ in false }.drive(innerRenoteDisplay.rx.isHidden).disposed(by: disposeBag)
        
        output.onOtherNote.asDriver(onErrorDriveWith: Driver.empty()).drive(actionStackView.rx.isHidden).disposed(by: disposeBag)
        output.onOtherNote.asDriver(onErrorDriveWith: Driver.empty()).drive(reactionsCollectionView.rx.isHidden).disposed(by: disposeBag)
        output.onOtherNote.asDriver(onErrorDriveWith: Driver.empty()).drive(separatorBorder.rx.isHidden).disposed(by: disposeBag)
        
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
    
    private func themeBinding() {
        let theme = Theme.shared.theme
        
        theme.map { $0.general.main }.subscribe(onNext: {
            self.tintColor = $0
        }).disposed(by: disposeBag)
        theme.map { $0.general.background }.bind(to: rx.backgroundColor).disposed(by: disposeBag)
        theme.map { $0.post.text }.subscribe(onNext: {
            for textView in [self.nameTextView, self.noteView] {
                guard let text = textView?.attributedText, text.length > 0 else { return }
                let mutableAttributed = NSMutableAttributedString(attributedString: text)
                mutableAttributed.addAttribute(.foregroundColor,
                                               value: $0,
                                               range: NSMakeRange(0, mutableAttributed.length - 1))
                textView?.attributedText = mutableAttributed
            }
            
        }).disposed(by: disposeBag)
        
//        Theme.shared.complete()
    }
    
    private func reactionColorBinding(_ cell: ReactionCell) {
        let theme = Theme.shared.theme
        
        theme.map { $0.post.reaction }.subscribe(onNext: {
            cell.nonselectedBackGroundColor = $0
        }).disposed(by: disposeBag)
        theme.map { $0.post.myReaction }.subscribe(onNext: {
            cell.selectedBackGroundColor = $0
        }).disposed(by: disposeBag)
        
        let postTheme = Theme.shared.getCurrentTheme().post
        
        cell.nonselectedBackGroundColor = postTheme.reaction
        cell.selectedBackGroundColor = postTheme.myReaction
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
        fileContainer.isHidden = isHidden
    }
    
    // MARK: Public Methods
    
    public func transform(with arg: Arg) -> NoteCell {
        setupView()
        
        let item = arg.item
        let isDetailMode = arg.isDetailMode
        isSkelton = item.isSkelton
        guard !item.isSkelton else { // SkeltonViewを表示する
            setupSkeltonMode()
            changeSkeltonState(on: true)
            return self
        }
        
        let hasFile = item.fileVisible && item.files.count > 0
        
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
        
        initializeComponent(hasFile: hasFile) // Initialize because NoteCell is reused by TableView.
        
        // main
        self.noteId = item.noteId
        userId = item.userId
        iconImageUrl = item.iconImageUrl
        delegate = arg.delegate
        
//        // YanagiTextと一対一にキャッシュを保存できるように、idをYanagiTextに渡す
//        noteView.setId(noteId: item.noteId)
//        nameTextView.setId(userId: item.userId)
        
        let viewModel = getViewModel(item: item, isDetailMode: isDetailMode)
        self.viewModel = viewModel
        
        viewModel.setCell()
        
        // file
        if hasFile {
            _ = fileContainer.transform(with: FileContainer.Arg(files: item.files,
                                                                noteId: noteId,
                                                                fileVisible: item.fileVisible,
                                                                delegate: arg.delegate))
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
        
        changeStateFileImage(isHidden: !hasFile)
//        fileContainer.initialize()
        
        replyButton.setTitle("", for: .normal)
        renoteButton.setTitle("", for: .normal)
        reactionButton.setTitle("", for: .normal)
        
        pollView.isHidden = true
        pollView.initialize()
        
        innerRenoteDisplay.isHidden = true
    }
    
    // MARK: Privates
    
    private func setupReactionCell(_ dataSource: CollectionViewSectionedDataSource<NoteCell.Reaction.Section>, _ collectionView: UICollectionView, _ indexPath: IndexPath) -> UICollectionViewCell {
        guard let viewModel = viewModel else { fatalError("Internal Error.") }
        
        let index = indexPath.row
        let reactionsModel = viewModel.reactionsModel
        
        guard let cell = reactionsCollectionView.dequeueReusableCell(withReuseIdentifier: "ReactionCell", for: indexPath) as? ReactionCell else { fatalError("Internal Error.") }
        
        if index < reactionsModel.count {
            let item = reactionsModel[index]
            
            let shapedCell = viewModel.setReactionCell(with: item, to: cell)
            shapedCell.delegate = self
            reactionColorBinding(shapedCell)
            
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
        
        skeltonCover.isSkeletonable = true
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
            
            skeltonCover.showAnimatedGradientSkeleton()
        } else {
            nameTextView.hideSkeleton()
            iconView.hideSkeleton()
            
            skeltonCover.hideSkeleton()
            skeltonCover.isHidden = true
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
            delegate?.updateMyReaction(targetNoteId: noteId, rawReaction: reaction, plus: true)
        } else {
            viewModel.cancelReaction(noteId: noteId)
            delegate?.updateMyReaction(targetNoteId: noteId, rawReaction: reaction, plus: false)
        }
    }
    
    // MARK: IBAction
    
    @IBAction func tappedReply(_ sender: Any) {
        guard let delegate = delegate, let noteModel = noteModel else { return }
        delegate.tappedReply(note: noteModel)
    }
    
    @IBAction func tappedRenote(_ sender: Any) {
        guard let delegate = delegate, let noteModel = noteModel else { return }
        delegate.tappedRenote(note: noteModel)
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
