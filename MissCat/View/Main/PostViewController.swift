//
//  PostViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/21.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import AVKit
import iOSPhotoEditor
import RxCocoa
import RxDataSources
import RxSwift
import UIKit

typealias AttachmentsDataSource = RxCollectionViewSectionedReloadDataSource<PostViewController.AttachmentsSection>
class PostViewController: UIViewController, UITextViewDelegate, UICollectionViewDelegate {
    // MARK: View
    
    @IBOutlet weak var attachmentCollectionView: UICollectionView!
    
    @IBOutlet weak var cancelButton: UIButton!
    @IBOutlet weak var submitButton: UIButton!
    @IBOutlet weak var visibilityButton: UIButton!
    @IBOutlet weak var iconImageView: UIImageView!
    
    @IBOutlet weak var innerNoteCell: UIView!
    @IBOutlet weak var markLabel: UILabel!
    @IBOutlet weak var innerIconView: UIImageView!
    @IBOutlet weak var innerNoteLabel: UILabel!
    
    @IBOutlet weak var mainStackView: UIStackView!
    @IBOutlet weak var mainTextView: PostTextView!
    @IBOutlet weak var bottomConstraint: NSLayoutConstraint!
    
    @IBOutlet weak var bottomStackView: UIStackView!
    @IBOutlet weak var addLocationButon: UIButton!
    
    private lazy var cwTextView = self.generateCwTextView()
    private lazy var toolBar = UIToolbar()
    private lazy var counter = UIBarButtonItem(title: "1500", style: .done, target: self, action: nil)
    private lazy var musicButton = UIBarButtonItem(title: "headphones-alt", style: .plain, target: self, action: nil)
    
    // MARK: Vars
    
    var homeViewController: HomeViewController?
    
    private var owner: SecureUser?
    private var postType: PostType = .Post
    private var targetNote: NoteCell.Model?
    
    private var viewModel: PostViewModel?
    
    private let disposeBag = DisposeBag()
    
    // MARK: Life Cycle
        
    /// 引用RN / リプライの場合に、対象ノートのモデルを受け渡す
    /// - Parameters:
    ///   - note: note model
    ///   - type: PostType
    
    func setup(owner: SecureUser, note: NoteCell.Model?, type: PostType) {
        self.owner = owner
        self.targetNote = note
        self.postType = type
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let viewModel = getViewModel()
        let dataSource = setupDataSource()
        binding(viewModel, dataSource)
        setupComponent(with: viewModel)
        setTheme()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillShow(_:)),
                                               name: UIResponder.keyboardWillShowNotification,
                                               object: nil)
        
        viewModel.transform()
        self.viewModel = viewModel
    }
    
    private func getViewModel() -> PostViewModel {
        let input: PostViewModel.Input = .init(owner: owner,
                                               type: postType,
                                               targetNote: targetNote,
                                               rxCwText: cwTextView.rx.text,
                                               rxMainText: mainTextView.rx.text,
                                               cancelTrigger: cancelButton.rx.tap.asObservable(),
                                               submitTrigger: submitButton.rx.tap.asObservable(),
                                               addNowPlayingInfoTrigger: musicButton.rx.tap.asObservable(),
                                               visibilitySettingTrigger: visibilityButton.rx.tap.asObservable())
        let viewModel = PostViewModel(with: input, and: disposeBag)
        return viewModel
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        mainTextView.becomeFirstResponder()
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        iconImageView.layer.cornerRadius = iconImageView.frame.width / 2
        innerIconView.layer.cornerRadius = innerIconView.frame.width / 2
    }
    
    // MARK: Design
    
    private func setTheme() {
        if let colorPattern = Theme.shared.currentModel?.colorPattern.ui {
            view.backgroundColor = colorPattern.base
            markLabel.textColor = colorPattern.text
            innerNoteLabel.textColor = colorPattern.sub0
        }
    }
    
    /// ステータスバーの文字色
    override var preferredStatusBarStyle: UIStatusBarStyle {
        let currentColorMode = Theme.shared.currentModel?.colorMode ?? .light
        return currentColorMode == .light ? UIStatusBarStyle.default : UIStatusBarStyle.lightContent
    }
    
    private func generateCwTextView() -> PostTextView {
        let cwTextView: PostTextView = .init()
//        let separator: UIView = .init()
//
//        separator.translatesAutoresizingMaskIntoConstraints = false
//        cwTextView.addSubview(separator)
//
//        // AutoLayout
//        self.view.addConstraint([ NSLayoutConstraint(item: separator,
//                                  attribute: .width,
//                                  relatedBy: .equal,
//                                  toItem: cwTextView,
//                                  attribute: .width,
//                                  multiplier: 1.0,
//                                  constant: 0)])
//
//        cwTextView.addConstraints([
//            NSLayoutConstraint(item: separator,
//                               attribute: .width,
//                               relatedBy: .equal,
//                               toItem: cwTextView,
//                               attribute: .width,
//                               multiplier: 1.0,
//                               constant: 0),
//
//            NSLayoutConstraint(item: separator,
//                               attribute: .height,
//                               relatedBy: .equal,
//                               toItem: cwTextView,
//                               attribute: .height,
//                               multiplier: 0,
//                               constant: 1),
//
//            NSLayoutConstraint(item: separator,
//                               attribute: .centerX,
//                               relatedBy: .equal,
//                               toItem: cwTextView,
//                               attribute: .centerX,
//                               multiplier: 1.0,
//                               constant: 0),
//
//            NSLayoutConstraint(item: separator,
//                               attribute: .leading,
//                               relatedBy: .equal,
//                               toItem: cwTextView,
//                               attribute: .leading,
//                               multiplier: 1.0,
//                               constant: 0)
//        ])
        
        return cwTextView
    }
    
    // MARK: Setup
    
    private func setupComponent(with viewModel: PostViewModel) {
        setupCollectionView()
        setupTextView(viewModel)
        setupNavItem()
        
        innerNoteCell.isHidden = targetNote == nil
        attachmentCollectionView.isHidden = true
        markLabel.font = .awesomeSolid(fontSize: 11.0)
        
        view.setTapGesture(disposeBag, closure: {
            self.mainTextView.becomeFirstResponder()
        })
    }
    
    private func setupDataSource() -> AttachmentsDataSource {
        let dataSource = AttachmentsDataSource(
            configureCell: { dataSource, _, indexPath, _ in
                self.setupCell(dataSource, self.attachmentCollectionView, indexPath)
            }
        )
        
        return dataSource
    }
    
    private func binding(_ viewModel: PostViewModel, _ dataSource: AttachmentsDataSource) {
        let output = viewModel.output
        
        output.iconImage.drive(iconImageView.rx.image).disposed(by: disposeBag)
        
        output.counter
            .asObservable()
            .bind(to: counter.rx.title)
            .disposed(by: disposeBag)
        
        output.attachments.map {
            guard $0.count == 1 else { return true }
            return $0[0].items.count == 0
        }.bind(to: attachmentCollectionView.rx.isHidden).disposed(by: disposeBag)
        
        output.attachments
            .bind(to: attachmentCollectionView.rx.items(dataSource: dataSource))
            .disposed(by: disposeBag)
        
        output.innerIcon
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(innerIconView.rx.image)
            .disposed(by: disposeBag)
        
        output.innerNote
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(innerNoteLabel.rx.text)
            .disposed(by: disposeBag)
        
        output.mark
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(markLabel.rx.text)
            .disposed(by: disposeBag)
        
        output.visibilityText
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(visibilityButton.rx.title(for: .normal))
            .disposed(by: disposeBag)
        
        // trigger
        
        output.addCwTextViewTrigger
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: { _ in self.addCwTextView() })
            .disposed(by: disposeBag)
        
        output.removeCwTextViewTrigger
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: { _ in self.removeCwTextView() })
            .disposed(by: disposeBag)
        
        output.dismissTrigger
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: {
                self.mainTextView.resignFirstResponder()
                self.dismiss(animated: true, completion: nil)
            })
            .disposed(by: disposeBag)
        
        output.presentVisibilityMenuTrigger
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: {
                self.presentVisibilityMenu()
            })
            .disposed(by: disposeBag)
        
        output.nowPlaying
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(musicButton.rx.isEnabled)
            .disposed(by: disposeBag)
    }
    
    private func setupCollectionView() {
        attachmentCollectionView.register(UINib(nibName: "AttachmentCell", bundle: nil), forCellWithReuseIdentifier: "AttachmentCell")
        attachmentCollectionView.rx.setDelegate(self).disposed(by: disposeBag)
        
        let flowLayout = UICollectionViewFlowLayout()
        let size = view.frame.width / 3
        
        flowLayout.itemSize = CGSize(width: size, height: attachmentCollectionView.frame.height)
        flowLayout.scrollDirection = .horizontal
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        attachmentCollectionView.collectionViewLayout = flowLayout
    }
    
    private func setupTextView(_ viewModel: PostViewModel) {
        // above toolbar
        setupToolBar(with: viewModel)
        
        // text & color
        let normalTextColor = Theme.shared.currentModel?.colorPattern.ui.text ?? .black
        let placeholderColor = Theme.shared.currentModel?.colorPattern.ui.sub2 ?? .lightGray
        
        mainTextView.setPlaceholder("What's happening?")
        mainTextView.setColor(normalText: normalTextColor,
                              placeholder: placeholderColor)
        
        cwTextView.setPlaceholder("-注釈をここに書く-")
        cwTextView.setColor(normalText: normalTextColor,
                            placeholder: placeholderColor)
    }
    
    private func setupToolBar(with viewModel: PostViewModel) {
        let flexibleItem = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        let cameraButton = UIBarButtonItem(title: "camera", style: .plain, target: self, action: nil)
        let imageButton = UIBarButtonItem(title: "images", style: .plain, target: self, action: nil)
        let pollButton = UIBarButtonItem(title: "poll", style: .plain, target: self, action: nil)
        let nsfwButton = UIBarButtonItem(title: "eye", style: .plain, target: self, action: nil)
        let emojiButton = UIBarButtonItem(title: "laugh-squint", style: .plain, target: self, action: nil)
        
        counter.setTitleTextAttributes([NSAttributedString.Key.font: UIFont(name: "Helvetica", size: 14.0)!], for: .normal)
        counter.setTitleTextAttributes([NSAttributedString.Key.font: UIFont(name: "Helvetica", size: 14.0)!], for: .selected)
        
        cameraButton.rx.tap.subscribe { _ in self.pickImage(type: .camera) }.disposed(by: disposeBag)
        imageButton.rx.tap.subscribe { _ in self.pickImage(type: .photoLibrary) }.disposed(by: disposeBag)
        pollButton.rx.tap.subscribe { _ in self.addEditablePoll() }.disposed(by: disposeBag)
        nsfwButton.rx.tap.subscribe { _ in self.showNSFWSettings() }.disposed(by: disposeBag)
        emojiButton.rx.tap.subscribe { _ in self.showReactionGen() }.disposed(by: disposeBag)
        
        addLocationButon.isHidden = true // 次アップデートで機能追加する
        toolBar.setItems([cameraButton, imageButton,
                          pollButton,
                          nsfwButton, musicButton,
                          flexibleItem, flexibleItem,
                          emojiButton, counter], animated: true)
        toolBar.sizeToFit()
        
        change2AwesomeFont(buttons: [cameraButton, imageButton, pollButton, musicButton, nsfwButton, emojiButton])
        mainTextView.inputAccessoryView = toolBar
    }
    
    private func setupNavItem() {
        let fontSize: CGFloat = 17.0
        
        cancelButton.titleLabel?.font = .awesomeSolid(fontSize: fontSize)
        submitButton.titleLabel?.font = .awesomeSolid(fontSize: fontSize)
        visibilityButton.titleLabel?.font = .awesomeSolid(fontSize: fontSize)
    }
    
    private func setupCell(_ dataSource: CollectionViewSectionedDataSource<PostViewController.AttachmentsSection>, _ collectionView: UICollectionView, _ indexPath: IndexPath) -> UICollectionViewCell {
        let index = indexPath.row
        let item = dataSource.sectionModels[0].items[index]
        
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "AttachmentCell", for: indexPath) as? AttachmentCell else { fatalError("Internal Error.") }
        
        if item.nsfw {
            setImageNSFW(to: cell)
        }
        
        cell.tappedImage.subscribe(onNext: { id in
            guard item.id == id else { return }
            
            self.showPhotoEditor(with: item.image).subscribe(onNext: { editedImage in // 画像エディタを表示
                guard let editedImage = editedImage else { return }
                self.viewModel?.updateFile(id: id, edited: editedImage)
                
            }).disposed(by: self.disposeBag)
            
        }).disposed(by: disposeBag)
        
        cell.tappedDiscardButton.subscribe(onNext: { id in
            self.viewModel?.removeAttachmentView(id)
        }).disposed(by: disposeBag)
        
        return cell.setupCell(item)
    }
    
    private func showReactionGen() {
        guard let reactionGen = getViewController(name: "reaction-gen") as? ReactionGenViewController else { return }
        
        reactionGen.onPostViewController = true
        reactionGen.selectedEmoji.subscribe(onNext: { emojiModel in // ReactionGenで絵文字が選択されたらに送られてくる
            self.insertCustomEmoji(with: emojiModel)
            reactionGen.dismiss(animated: true, completion: nil)
        }).disposed(by: disposeBag)
        
        presentWithSemiModal(reactionGen, animated: true, completion: nil)
    }
    
    private func showNSFWSettings() {
        let panelMenu = PanelMenuViewController()
        let menuItems: [PanelMenuViewController.MenuItem] = [.init(title: "投稿に注釈をつける", awesomeIcon: "sticky-note", order: 0),
                                                             .init(title: "画像を閲覧注意にする", awesomeIcon: "image", order: 1)]
        
        panelMenu.setupMenu(items: menuItems)
        panelMenu.tapTrigger.asDriver(onErrorDriveWith: Driver.empty()).drive(onNext: { order in // どのメニューがタップされたのか
            guard order >= 0 else { return }
            panelMenu.dismiss(animated: true, completion: nil)
            
            if order == 0 {
                self.viewModel?.changeCwState()
            } else {
                self.viewModel?.changeImageNsfwState()
            }
        }).disposed(by: disposeBag)
        
        present(panelMenu, animated: true, completion: nil)
    }
    
    private func addEditablePoll() {
        let editablePoll = EditablePollView()
        editablePoll.translatesAutoresizingMaskIntoConstraints = false
        
        mainStackView.addArrangedSubview(editablePoll)
        view.addConstraint(NSLayoutConstraint(item: editablePoll,
                                              attribute: .height,
                                              relatedBy: .equal,
                                              toItem: editablePoll,
                                              attribute: .height,
                                              multiplier: 0,
                                              constant: editablePoll.height))
    }
    
    private func addCwTextView() {
        cwTextView.isScrollEnabled = false // 高さを可変に
        mainStackView.insertArrangedSubview(cwTextView, at: 0)
    }
    
    private func removeCwTextView() {
        cwTextView.removeFromSuperview()
    }
    
    private func setImageNSFW(to parentView: UIView) {
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
        nsfwLabel.text = "NSFW"
        nsfwLabel.center = parentView.center
        nsfwLabel.textAlignment = .center
        nsfwLabel.numberOfLines = 2
        nsfwLabel.textColor = .lightGray
        
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
    }
    
    private func getViewController(name: String) -> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyboard.instantiateViewController(withIdentifier: name)
        
        return viewController
    }
    
    private func insertCustomEmoji(with emojiModel: EmojiView.EmojiModel) {
        //        guard let imageUrl = emojiModel.customEmojiUrl else { return }
        //        let targetView = MFMEngine.generateAsyncImageView(imageUrl: imageUrl)
        //
        if let selectedTextRange = mainTextView.selectedTextRange {
            guard let emoji = emojiModel.isDefault ? emojiModel.defaultEmoji : ":\(emojiModel.rawEmoji):" else { return }
            mainTextView.replace(selectedTextRange,
                                 withText: emoji)
        }
    }
    
    // キーボードの高さに合わせてcomponentの高さを調整する
    private func fitToKeyboard(keyboardHeight: CGFloat) {
        layoutIfNeeded(to: [bottomStackView, toolBar])
        bottomConstraint.constant = keyboardHeight
    }
    
    // MARK: Visibility
    
    private func presentVisibilityMenu() {
        let frameSize = CGSize(width: view.frame.width / 3, height: 50 * 3)
        let menus: [DropdownMenu] = [.init(awesomeIcon: "globe", title: "パブリック"),
                                     .init(awesomeIcon: "home", title: "ホーム"),
                                     .init(awesomeIcon: "lock", title: "フォロワー")]
        let selected = presentDropdownMenu(with: menus, size: frameSize, sourceRect: visibilityButton.frame)
        
        selected?.subscribe(onNext: { selectedIndex in
            switch selectedIndex {
            case 0:
                self.viewModel?.changeVisibility(to: .public)
            case 1:
                self.viewModel?.changeVisibility(to: .home)
            case 2:
                self.viewModel?.changeVisibility(to: .followers)
            default:
                break
            }
        }).disposed(by: disposeBag)
    }
    
    // MARK: Utilities
    
    private func change2AwesomeFont(buttons: [UIBarButtonItem]) {
        buttons.forEach { button in
            button.setTitleTextAttributes([NSAttributedString.Key.font: UIFont.awesomeSolid(fontSize: 17.0)!], for: .normal)
            button.setTitleTextAttributes([NSAttributedString.Key.font: UIFont.awesomeSolid(fontSize: 17.0)!], for: .selected)
            button.setTitleTextAttributes([NSAttributedString.Key.font: UIFont.awesomeSolid(fontSize: 17.0)!], for: .disabled)
        }
    }
    
    // MARK: Delegate
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        transformAttachment(disposeBag: disposeBag, picker: picker, didFinishPickingMediaWithInfo: info) { originalImage, editedImage, videoUrl in
            if let originalImage = originalImage, let editedImage = editedImage {
                self.viewModel?.stackFile(original: originalImage, edited: editedImage)
            } else if let videoUrl = videoUrl {
                self.viewModel?.stackFile(videoUrl: videoUrl)
            }
        }
    }
    
    // MARK: NotificationCenter
    
    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let userInfo = notification.userInfo as? [String: Any],
            let keyboardInfo = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
        
        let keyboardSize = keyboardInfo.cgRectValue.size
        fitToKeyboard(keyboardHeight: keyboardSize.height)
    }
}

extension PostViewController {
    enum PostType {
        case Post
        case Reply
        case CommentRenote
    }
}

extension PostViewController {
    struct AttachmentsSection {
        var items: [Item]
    }
    
    class Attachments {
        var id: String
        
        var image: UIImage
        var type: Type
        var nsfw: Bool = false
        
        init(id: String, image: UIImage, type: Type) {
            self.id = id
            self.image = image
            self.type = type
        }
        
        func changeNsfwState(_ nsfw: Bool) -> Attachments {
            self.nsfw = nsfw
            return self
        }
    }
    
    enum `Type` {
        case Image
        case Video
    }
}

extension PostViewController.AttachmentsSection: SectionModelType {
    typealias Item = PostViewController.Attachments
    
    init(original: PostViewController.AttachmentsSection, items: [Item]) {
        self = original
        self.items = items
    }
}

/// 高さ可変でPlaceholderを持つTextView
class PostTextView: UITextView, UITextViewDelegate {
    private var placeholder: String?
    private var placeholderColor: UIColor?
    private var normalTextColor: UIColor?
    
    // MARK: LifeCycle
    
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        delegate = self
        isScrollEnabled = false // 高さが可変になる
        backgroundColor = .clear
        font = .systemFont(ofSize: 17.0)
    }
    
    // MARK: Set
    
    func setPlaceholder(_ text: String) {
        placeholder = text
        self.text = placeholder
    }
    
    func setColor(normalText: UIColor, placeholder: UIColor) {
        normalTextColor = normalText
        placeholderColor = placeholder
        textColor = placeholder
    }
    
    // MARK: Delegate
    
    func textViewDidBeginEditing(_ textView: UITextView) {
        if textColor == placeholderColor {
            text = ""
            textColor = normalTextColor ?? .black
        }
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        if text == "" {
            text = placeholder
            textColor = placeholderColor ?? .white
        }
    }
}
