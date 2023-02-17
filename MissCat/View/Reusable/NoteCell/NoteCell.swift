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

protocol NoteCellDelegate {
    func tappedReply(note: NoteCell.Model)
    func tappedRenote(note: NoteCell.Model)
    func tappedReaction(owner: SecureUser, reactioned: Bool, noteId: String, iconUrl: String?, displayName: String, username: String, hostInstance: String, note: NSAttributedString, hasFile: Bool, hasMarked: Bool, myReaction: String?)
    func tappedOthers(note: NoteCell.Model)
    
    func move2PostDetail(item: NoteCell.Model)
    
    func updateMyReaction(targetNoteId: String, rawReaction: String, plus: Bool)
    func vote(choice: [Int], to noteId: String, owner: SecureUser)
    
    func tappedLink(text: String, owner: SecureUser)
    func move2Profile(userId: String, owner: SecureUser)
    
    func showImage(_ urls: [URL], start startIndex: Int)
    func playVideo(url: String)
}

private typealias ViewModel = NoteCellViewModel
typealias ReactionsDataSource = RxCollectionViewSectionedReloadDataSource<NoteCell.Reaction.Section>

class NoteCell: UITableViewCell, UITextViewDelegate, ReactionCellDelegate, UICollectionViewDelegate, ComponentType {
    struct Arg {
        var item: NoteCell.Model
        var isDetailMode: Bool = false
        var delegate: NoteCellDelegate?
        var owner: SecureUser
    }
    
    typealias Transformed = NoteCell
    
    // MARK: IBOutlet (UIView)
    
    @IBOutlet weak var nameTextView: MisskeyTextView!
    
    @IBOutlet weak var iconView: UIImageView!
    
    @IBOutlet weak var agoLabel: UILabel!
    
    @IBOutlet weak var noteView: MisskeyTextView!
    
    @IBOutlet weak var reactionsCollectionView: UICollectionView!
    
    @IBOutlet weak var skeltonCover: UIView!
    @IBOutlet weak var fileContainer: FileContainer!
    @IBOutlet weak var pollView: PollView!
    @IBOutlet weak var urlPreviewer: UrlPreviewer!
    
    @IBOutlet weak var innerRenoteDisplay: UIView!
    @IBOutlet weak var innerIconView: UIImageView!
    @IBOutlet weak var innerNameTextView: MisskeyTextView!
    @IBOutlet weak var innerNoteTextView: MisskeyTextView!
    @IBOutlet weak var innerAgoLabel: UILabel!
    
    @IBOutlet weak var actionStackView: UIStackView!
    @IBOutlet weak var replyButton: UIButton!
    @IBOutlet weak var renoteButton: UIButton!
    @IBOutlet weak var reactionButton: UIButton!
    @IBOutlet weak var othersButton: UIButton!
    
    @IBOutlet weak var separatorBorder: UIView!
    @IBOutlet weak var replyIndicator: UIView!
    
    @IBOutlet weak var mainStackView: UIStackView!
    
    @IBOutlet weak var catIcon: UIImageView!
    @IBOutlet weak var catYConstraint: NSLayoutConstraint!
    
    // MARK: IBOutlet (Constraint)
    
    @IBOutlet weak var nameHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var displayName2MainStackConstraint: NSLayoutConstraint!
    @IBOutlet weak var icon2MainStackConstraint: NSLayoutConstraint!
    @IBOutlet weak var reactionCollectionHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var pollViewHeightConstraint: NSLayoutConstraint!
    
    // MARK: Public Var
    
    var delegate: NoteCellDelegate?
    
    var noteId: String?
    var userId: String?
    var hostInstance: String?
    var iconImageUrl: String?
    var owner: SecureUser?
    
    // MARK: Private Var
    
    private let disposeBag = DisposeBag()
    private var reactionsDataSource: ReactionsDataSource?
    private var viewModel: ViewModel?
    
    private var renoteTarget: NoteCell.Model?
    private var noteModel: NoteCell.Model?
    private var onOtherNote: Bool = false
    private var isSkelton: Bool = false
    
    private func getViewModel(item: NoteCell.Model, isDetailMode: Bool, owner: SecureUser) -> ViewModel {
        let input: ViewModel.Input = .init(cellModel: item,
                                           isDetailMode: isDetailMode,
                                           owner: owner,
                                           noteYanagi: noteView,
                                           nameYanagi: nameTextView)
        
        let viewModel = NoteCellViewModel(with: input, and: disposeBag)
        
        noteModel = item
        binding(viewModel: viewModel, noteId: item.noteEntity.noteId ?? "")
        return viewModel
    }
    
    // MARK: Life Cycle
    
    override func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority, verticalFittingPriority: UILayoutPriority) -> CGSize {
        contentView.bounds.size = targetSize
        contentView.layoutIfNeeded()
        return super.systemLayoutSizeFitting(targetSize,
                                             withHorizontalFittingPriority: horizontalFittingPriority,
                                             verticalFittingPriority: verticalFittingPriority)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setupView()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        setupView()
        setupComponents()
        
        nameTextView.transformText() // TODO: せっかくisHiddenがどうこうやってたのが反映されていないような気がする
        noteView.transformText()
        
        innerNameTextView.renderViewStrings()
        innerNoteTextView.renderViewStrings()
        
        innerNameTextView.transformText()
        innerNoteTextView.transformText()
        
        if onOtherNote {
            nameTextView.renderViewStrings()
            noteView.renderViewStrings()
        }
        
        if isSkelton {
            let gradient = SkeletonGradient(baseColor: Theme.shared.currentModel?.colorPattern.ui.sub3 ?? .lightGray)
            // 以下２行を書くとskeltonViewが正常に表示される
            layoutIfNeeded()
            skeltonCover.updateAnimatedGradientSkeleton(usingGradient: gradient)
        }
    }
    
    private lazy var setupView: (() -> Void) = { // 必ず一回しか読み込まれない
        self.setupProfileGesture() // プロフィールに飛ぶtapgestureを設定する
        self.setupCollectionView()
        self.setupFileContainer()
        self.setupInnerRenoteDisplay()
        self.setupPoll()
        self.selectedBackgroundView = UIView()
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
        
        innerIconView.layer.cornerRadius = innerIconView.frame.height / 2
        
        noteView.delegate = self
        noteView.isUserInteractionEnabled = true
        
        innerNoteTextView.delegate = self
        innerNoteTextView.isUserInteractionEnabled = true
        
        skeltonCover.isUserInteractionEnabled = false
        
        catYConstraint.constant = (-1) * catIcon.frame.width / 4 + 2
        catYConstraint.constant -= sqrt(abs(pow(iconView.layer.cornerRadius, 2) - pow(catIcon.frame.width / 2, 2)))
    }
    
    private func setupFileContainer() {
        fileContainer.clipsToBounds = true
        fileContainer.layer.cornerRadius = 10
        fileContainer.layer.borderColor = UIColor.lightGray.cgColor
        fileContainer.layer.borderWidth = 0.3
        fileContainer.layer.backgroundColor = UIColor.clear.cgColor
    }
    
    private func setupInnerRenoteDisplay() {
        innerRenoteDisplay.layer.borderWidth = 0.5
        innerRenoteDisplay.layer.borderColor = UIColor.systemBlue.cgColor
        innerRenoteDisplay.layer.cornerRadius = 5
        
        innerRenoteDisplay.setTapGesture(disposeBag) {
            guard let renoteTarget = self.renoteTarget else { return }
            self.delegate?.move2PostDetail(item: renoteTarget)
        }
    }
    
    private func setupPoll() {
        pollView.voteTriggar.asDriver(onErrorDriveWith: Driver.empty()).drive(onNext: { ids in
            guard let noteId = self.noteId, let owner = self.owner else { return }
            self.viewModel?.updateVote(choices: ids)
            self.delegate?.vote(choice: ids, to: noteId, owner: owner)
        }).disposed(by: disposeBag)
    }
    
    private func binding(viewModel: ViewModel, noteId: String) {
        let output = viewModel.output
            
        // reaction
        reactionsCollectionView.delegate = nil
        reactionsCollectionView.dataSource = nil
        
        let dataSource = setupDataSource()
        output.reactions
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(reactionsCollectionView.rx.items(dataSource: dataSource))
            .disposed(by: disposeBag)

        output.reactions.asDriver(onErrorDriveWith: Driver.empty()).map { // リアクションの数が0のときはreactionsCollectionViewを非表示に
            guard $0.count == 1 else { return true }
            return $0[0].items.count == 0
        }.drive(reactionsCollectionView.rx.isHidden).disposed(by: disposeBag)
//
        output.reactions.asDriver(onErrorDriveWith: Driver.empty()).map { // リアクションの数によってreactionsCollectionViewの高さを調節
            guard $0.count == 1 else { return 30 }
            let count = $0[0].items.count
            let step = ceil(Double(count) / 5)

            return CGFloat(step * 40)
        }.drive(reactionCollectionHeightConstraint.rx.constant).disposed(by: disposeBag)
        
        output.url.asDriver(onErrorDriveWith: Driver.empty()).drive(onNext: { url in
            guard !url.isEmpty else { return }
            self.urlPreviewer.isHidden = false
            _ = self.urlPreviewer.transform(with: .init(url: url, owner: self.owner))
        }).disposed(by: disposeBag)
        
        // Renote With Comment
        
        output.commentRenoteTarget
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: { self.renoteTarget = $0 })
            .disposed(by: disposeBag)
        
        output.commentRenoteTarget
            .asDriver(onErrorDriveWith: Driver.empty())
            .map { $0.noteEntity.iconImage }
            .drive(innerIconView.rx.image)
            .disposed(by: disposeBag)
        
        output.commentRenoteTarget
            .asDriver(onErrorDriveWith: Driver.empty())
            .map { $0.shapedNote }
            .compactMap { $0 }
            .drive(onNext: { mfmString in
                self.innerNoteTextView.attributedText = mfmString.attributed
                mfmString.mfmEngine.renderCustomEmojis(on: self.innerNoteTextView)
            }).disposed(by: disposeBag)
        
        output.commentRenoteTarget
            .asDriver(onErrorDriveWith: Driver.empty())
            .map { $0.shapedDisplayName }
            .compactMap { $0 }
            .drive(onNext: { mfmString in
                self.innerNameTextView.attributedText = mfmString.attributed
                mfmString.mfmEngine.renderCustomEmojis(on: self.innerNameTextView)
            }).disposed(by: disposeBag)
        
        output.commentRenoteTarget
            .asDriver(onErrorDriveWith: Driver.empty())
            .map { $0.noteEntity.ago.calculateAgo() }
            .drive(innerAgoLabel.rx.text).disposed(by: disposeBag)
        
        output.innerIconImage
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(innerIconView.rx.image)
            .disposed(by: disposeBag)
        
        output.commentRenoteTarget
            .asDriver(onErrorDriveWith: Driver.empty())
            .map { _ in false }
            .drive(innerRenoteDisplay.rx.isHidden)
            .disposed(by: disposeBag)
        
        // poll
        output.poll
            .asDriver(onErrorDriveWith: Driver.empty())
            .compactMap { $0 }
            .drive(onNext: { poll in
                self.pollView.isHidden = false
                self.pollView.setPoll(with: poll)
                self.pollViewHeightConstraint.constant = self.pollView.height
            }).disposed(by: disposeBag)
        
        // general
        output.ago
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(agoLabel.rx.text)
            .disposed(by: disposeBag)
        
        output.name
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(nameTextView.rx.attributedText)
            .disposed(by: disposeBag)
        
        output.shapedNote
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(noteView.rx.attributedText)
            .disposed(by: disposeBag)
        
        output.shapedNote.asDriver(onErrorDriveWith: Driver.empty())
            .map { $0 == nil }
            .drive(noteView.rx.isHidden)
            .disposed(by: disposeBag) // 画像onlyや投票onlyの場合、noteが存在しない場合がある→ noteViewを非表示にする
        
        output.iconImage
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(iconView.rx.image)
            .disposed(by: disposeBag)
        
        // constraint
        output.defaultConstraintActive.asDriver(onErrorDriveWith: Driver.empty())
            .map { UILayoutPriority(rawValue: $0 ? 999.5 : 900) }
            .drive(onNext: { self.displayName2MainStackConstraint.priority = $0 })
            .disposed(by: disposeBag)
        
        output.defaultConstraintActive.asDriver(onErrorDriveWith: Driver.empty())
            .map { UILayoutPriority(rawValue: $0 ? 999.5 : 900) }
            .drive(onNext: { self.icon2MainStackConstraint.priority = $0 })
            .disposed(by: disposeBag)
        
        // color
        output.mainColor
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: { self.innerRenoteDisplay.layer.borderColor = $0.cgColor })
            .disposed(by: disposeBag)
        
        output.backgroundColor
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(rx.backgroundColor)
            .disposed(by: disposeBag)
        
        output.backgroundColor
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(innerRenoteDisplay.rx.backgroundColor)
            .disposed(by: disposeBag)
        
        output.selectedBackgroundColor
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: { selectedBackgroundColor in
                self.selectedBackgroundView?.backgroundColor = selectedBackgroundColor
                self.contentView.backgroundColor = nil
            })
            .disposed(by: disposeBag)
        
        output.separatorBackgroundColor
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(separatorBorder.rx.backgroundColor)
            .disposed(by: disposeBag)
        
        output.separatorBackgroundColor
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: { self.fileContainer.layer.borderColor = $0.cgColor })
            .disposed(by: disposeBag)
        
        output.actionButtonColor
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: { color in
                [self.replyButton, self.renoteButton, self.reactionButton, self.othersButton].forEach {
                    $0?.setTitleColor(color, for: .normal)
                }
            })
            .disposed(by: disposeBag)
        
        // hidden
        Observable.combineLatest(output.isReplyTarget.asObservable(), output.onOtherNote.asObservable()) { $0 || $1 }
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(separatorBorder.rx.isHidden).disposed(by: disposeBag)
        
        output.isReplyTarget.map { !$0 }
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(replyIndicator.rx.isHidden)
            .disposed(by: disposeBag)
        
        output.onOtherNote
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(actionStackView.rx.isHidden)
            .disposed(by: disposeBag)
        
        output.onOtherNote
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(reactionsCollectionView.rx.isHidden)
            .disposed(by: disposeBag)
        
        output.replyLabel
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(replyButton.rx.title())
            .disposed(by: disposeBag)
        
        output.renoteLabel
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(renoteButton.rx.title())
            .disposed(by: disposeBag)
        
        output.reactionLabel
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(reactionButton.rx.title())
            .disposed(by: disposeBag)
        
        urlPreviewer.setTapGesture(disposeBag) {
            guard let previewdUrl = viewModel.state.previewedUrl,
                  let owner = self.owner else { return }
            self.delegate?.tappedLink(text: previewdUrl, owner: owner)
        }
    }
    
    private func setupProfileGesture() {
        let gestureTargets = [iconView, nameTextView]
        
        gestureTargets.forEach {
            guard let view = $0 else { return }
            view.setTapGesture(disposeBag) {
                guard let delegate = self.delegate,
                      let userId = self.userId,
                      let owner = self.owner else { return }
                delegate.move2Profile(userId: userId, owner: owner)
            }
        }
    }
    
    private func changeStateFileImage(isHidden: Bool) {
        fileContainer.isHidden = isHidden
    }
    
    // MARK: Public Methods
    
    func transform(with arg: Arg) -> NoteCell {
        setupView()
        
        let item = arg.item
        let noteEntity = item.noteEntity
        let isDetailMode = arg.isDetailMode
        isSkelton = item.type == .skelton
        guard !isSkelton else { // SkeltonViewを表示する
            setupSkeltonMode()
            changeSkeltonState(on: true)
            return self
        }
        
        let hasFile = item.fileVisible && noteEntity.files.count > 0 && !(noteEntity.hasCw && !isDetailMode)
        
        // Font
        noteView.font = UIFont(name: "Helvetica",
                               size: isDetailMode ? 15.0 : 11.0)
        nameTextView.font = UIFont(name: "Helvetica",
                                   size: 10.0)
        
        reactionsCollectionView.isHidden = true // リアクションが存在しない場合はHideする
        
        // 余白消す
        nameTextView.textContainerInset = .zero
        nameTextView.textContainer.lineFragmentPadding = 0
        
        changeSkeltonState(on: false)
        
        guard let noteId = noteEntity.noteId else { return NoteCell() }
        
        initializeComponent(hasFile: hasFile) // Initialize because NoteCell is reused by TableView.
        
        // Cat
        catIcon.isHidden = !noteEntity.isCat
        
        // main
        self.noteId = noteId
        owner = arg.owner
        userId = noteEntity.userId
        hostInstance = noteEntity.hostInstance
        iconImageUrl = noteEntity.iconImageUrl
        delegate = arg.delegate
        
        // ViewModel
        let viewModel = getViewModel(item: item, isDetailMode: isDetailMode, owner: arg.owner)
        self.viewModel = viewModel
        
        viewModel.setCell()
        
        // file
        setFile(with: item,
                hasFile: hasFile,
                noteId: noteId,
                delegate: arg.delegate)
        
        return self
    }
    
    private func setFile(with item: NoteCell.Model, hasFile: Bool, noteId: String, delegate: NoteCellDelegate?) {
        if hasFile {
            _ = fileContainer.transform(with: FileContainer.Arg(files: item.noteEntity.files,
                                                                noteId: noteId,
                                                                fileVisible: item.fileVisible,
                                                                delegate: delegate))
        }
    }
    
    func initializeComponent(hasFile: Bool) {
        viewModel?.prepareForReuse()
        delegate = nil
        noteId = nil
        userId = nil
        hostInstance = nil
        owner = nil
        
        backgroundColor = Theme.shared.currentModel?.colorPattern.ui.base ?? .white
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
        
        replyButton.setTitle("", for: .normal)
        renoteButton.setTitle("", for: .normal)
        reactionButton.setTitle("", for: .normal)
        
        pollView.isHidden = true
        pollView.initialize()
        
        urlPreviewer.isHidden = true
        urlPreviewer.initialize()
        
        innerRenoteDisplay.isHidden = true
        
        innerNameTextView.attributedText = nil
        innerNameTextView.resetViewString()
        
        innerNoteTextView.attributedText = nil
        innerNoteTextView.resetViewString()
        
        catIcon.isHidden = true
    }
    
    // MARK: Privates
    
    private func setupReactionCell(_ dataSource: CollectionViewSectionedDataSource<NoteCell.Reaction.Section>, _ collectionView: UICollectionView, _ indexPath: IndexPath) -> UICollectionViewCell {
        guard let viewModel = viewModel else { fatalError("Internal Error.") }
        
        let index = indexPath.row
        let reactionsModel = viewModel.reactionsModel
        
        guard let cell = reactionsCollectionView.dequeueReusableCell(withReuseIdentifier: "ReactionCell", for: indexPath) as? ReactionCell else { fatalError("Internal Error.") }
        
        cell.isUserInteractionEnabled = !viewModel.state.isMe // 自分の投稿ではリアクションをタップできないように
        if index < reactionsModel.count {
            let item = reactionsModel[index]
            
            let shapedCell = cell.transform(with: item)
            shapedCell.delegate = self
            
            return shapedCell
        }
        
        return cell
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
        backgroundColor = Theme.shared.currentModel?.colorPattern.ui.base ?? .white
        separatorBorder.backgroundColor = Theme.shared.currentModel?.colorPattern.ui.sub2 ?? .lightGray
    }
    
    private func changeSkeltonState(on: Bool) {
        if on {
            nameTextView.text = nil
            agoLabel.text = nil
            noteView.text = nil
            reactionsCollectionView.isHidden = true
            pollView.isHidden = true
            urlPreviewer.isHidden = true
            innerRenoteDisplay.isHidden = true
            
            let gradient = SkeletonGradient(baseColor: Theme.shared.currentModel?.colorPattern.ui.sub3 ?? .lightGray)
            
            nameTextView.showAnimatedGradientSkeleton(usingGradient: gradient)
            iconView.showAnimatedGradientSkeleton(usingGradient: gradient)
            skeltonCover.showAnimatedGradientSkeleton(usingGradient: gradient)
            
            isUserInteractionEnabled = false // skelton表示されたセルはタップできないように
        } else {
            nameTextView.hideSkeleton()
            iconView.hideSkeleton()
            
            skeltonCover.hideSkeleton()
            skeltonCover.isHidden = true
            isUserInteractionEnabled = true
        }
    }
    
    // MARK: DELEGATE
    
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        if let delegate = delegate, let owner = owner {
            delegate.tappedLink(text: URL.absoluteString, owner: owner)
        }
        
        return false
    }
    
    func tappedReaction(noteId: String, reaction: String, isRegister: Bool) {
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
        guard let delegate = delegate,
              let owner = owner,
              let noteId = self.noteId,
              let viewModel = viewModel,
              !viewModel.state.isMe else { return }
        
        delegate.tappedReaction(owner: owner,
                                reactioned: viewModel.state.reactioned,
                                noteId: noteId,
                                iconUrl: iconImageUrl,
                                displayName: viewModel.output.displayName,
                                username: viewModel.output.username,
                                hostInstance: hostInstance ?? "",
                                note: noteView.attributedText,
                                hasFile: false,
                                hasMarked: false,
                                myReaction: viewModel.state.myReaction)
        
        if viewModel.state.reactioned {
            viewModel.cancelReaction(noteId: noteId)
        }
    }
    
    @IBAction func tappedOthers(_ sender: Any) {
        guard let delegate = delegate, let noteModel = noteModel else { return }
        delegate.tappedOthers(note: noteModel)
    }
}
