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
class PostViewController: UIViewController, UITextViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UICollectionViewDelegate {
    @IBOutlet weak var attachmentCollectionView: UICollectionView!
    
    @IBOutlet weak var cancelButton: UIButton!
    @IBOutlet weak var submitButton: UIButton!
    @IBOutlet weak var iconImageView: UIImageView!
    
    @IBOutlet weak var mainTextView: UITextView!
    @IBOutlet weak var mainTextViewBottomConstraint: NSLayoutConstraint!
    
    @IBOutlet weak var bottomStackView: UIStackView!
    @IBOutlet weak var addLocationButon: UIButton!
    
    var homeViewController: HomeViewController?
    
    private var postType: PostType = .Post
    private var targetNoteCell: NoteCell?
    private var targetNote: NoteCell.Model?
    
    private var viewModel: PostViewModel?
    private lazy var toolBar = UIToolbar()
    private let disposeBag = DisposeBag()
    
    private lazy var counter = UIBarButtonItem(title: "1500", style: .done, target: self, action: nil)
    
    // MARK: Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let viewModel = PostViewModel(with: .init(type: postType, targetNote: targetNote), and: disposeBag)
        let dataSource = setupDataSource()
        binding(viewModel, dataSource)
        
        setupCollectionView()
        setupTextView(viewModel)
        setupNavItem()
        setupTargetNoteCell()
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillShow(_:)),
                                               name: UIResponder.keyboardWillShowNotification,
                                               object: nil)
        
        self.viewModel = viewModel
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        mainTextView.becomeFirstResponder()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        targetNote?.onOtherNote = false
        targetNote?.fileVisible = true
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        iconImageView.layer.cornerRadius = iconImageView.frame.width / 2
    }
    
    /// 引用RN / リプライの場合に、対象ノートのモデルを受け渡す
    /// - Parameters:
    ///   - note: note model
    ///   - type: PostType
    func setTargetNote(_ note: NoteCell.Model, type: PostType) {
        guard let noteCell = UINib(nibName: "NoteCell", bundle: nil).instantiate(withOwner: self, options: nil).first as? NoteCell else { return }
        
        note.onOtherNote = true
        note.fileVisible = false
        
        targetNote = note
        postType = type
        targetNoteCell = noteCell.transform(with: .init(item: note))
    }
    
    // MARK: Setup
    
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
        //        output.isSuccess.subscribe { _ in
        //
        //        }.disposed(by: disposeBag)
        
        cancelButton.rx.tap.asObservable().subscribe { _ in
            self.mainTextView.resignFirstResponder()
            self.dismiss(animated: true, completion: nil)
        }.disposed(by: disposeBag)
        
        submitButton.rx.tap.asObservable().subscribe { _ in
            viewModel.submitNote(self.mainTextView.text)
            DispatchQueue.main.async { self.dismiss(animated: true, completion: nil) }
        }.disposed(by: disposeBag)
        
        mainTextView.rx.text.asObservable().map {
            guard let text = $0 else { return $0 ?? "" }
            return String(1500 - text.count)
        }.bind(to: counter.rx.title).disposed(by: disposeBag)
        
        output.attachments.map { $0.count == 0 }.bind(to: attachmentCollectionView.rx.isHidden).disposed(by: disposeBag)
        output.attachments.bind(to: attachmentCollectionView.rx.items(dataSource: dataSource)).disposed(by: disposeBag)
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
        // miscs
        mainTextView.rx.setDelegate(self).disposed(by: disposeBag)
        mainTextView.textColor = .lightGray
        
        // above toolbar
        let flexibleItem = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        let cameraButton = UIBarButtonItem(title: "camera", style: .plain, target: self, action: nil)
        let imageButton = UIBarButtonItem(title: "images", style: .plain, target: self, action: nil)
        let pollButton = UIBarButtonItem(title: "poll", style: .plain, target: self, action: nil)
        let locationButton = UIBarButtonItem(title: "map-marker-alt", style: .plain, target: self, action: nil)
        let nsfwButton = UIBarButtonItem(title: "eye", style: .plain, target: self, action: nil)
        let emojiButton = UIBarButtonItem(title: "laugh-squint", style: .plain, target: self, action: nil)
        
        counter.setTitleTextAttributes([NSAttributedString.Key.font: UIFont(name: "Helvetica", size: 14.0)!], for: .normal)
        counter.setTitleTextAttributes([NSAttributedString.Key.font: UIFont(name: "Helvetica", size: 14.0)!], for: .selected)
        
        cameraButton.rx.tap.subscribe { _ in self.pickImage(type: .camera) }.disposed(by: disposeBag)
        imageButton.rx.tap.subscribe { _ in self.pickImage(type: .photoLibrary) }.disposed(by: disposeBag)
        pollButton.rx.tap.subscribe { _ in }.disposed(by: disposeBag)
        locationButton.rx.tap.subscribe { _ in viewModel.getLocation() }.disposed(by: disposeBag)
        nsfwButton.rx.tap.subscribe { _ in self.showNSFWSettings() }.disposed(by: disposeBag)
        emojiButton.rx.tap.subscribe { _ in self.showReactionGen() }.disposed(by: disposeBag)
        
        addLocationButon.isHidden = true // 次アップデートで機能追加する
        toolBar.setItems([cameraButton, imageButton,
                          // 次アップデートで機能追加する
                          // pollButton, locationButton,
                          nsfwButton,
                          flexibleItem, flexibleItem,
                          emojiButton, counter], animated: true)
        toolBar.sizeToFit()
        
        change2AwesomeFont(buttons: [cameraButton, imageButton, pollButton, locationButton, nsfwButton, emojiButton])
        mainTextView.inputAccessoryView = toolBar
    }
    
    private func setupNavItem() {
        let fontSize: CGFloat = 17.0
        
        cancelButton.titleLabel?.font = .awesomeSolid(fontSize: fontSize)
        submitButton.titleLabel?.font = .awesomeSolid(fontSize: fontSize)
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
    
    private func setupTargetNoteCell() {
        guard let targetCell = targetNoteCell else { return }
        
        targetCell.frame = CGRect(x: targetCell.frame.origin.x,
                                  y: targetCell.frame.origin.y,
                                  width: bottomStackView.frame.width,
                                  height: targetCell.frame.height)
        bottomStackView.addArrangedSubview(targetCell)
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
        guard let panelMenu = getViewController(name: "panel-menu") as? PanelMenuViewController else { return }
        let menuItems: [PanelMenuViewController.MenuItem] = [.init(title: "投稿を閲覧注意にする", awesomeIcon: "sticky-note", order: 0),
                                                             .init(title: "画像を閲覧注意にする", awesomeIcon: "image", order: 1)]
        
        panelMenu.setPanelTitle("NSFWの設定")
        panelMenu.setupMenu(items: menuItems)
        panelMenu.tapTrigger.asDriver(onErrorDriveWith: Driver.empty()).drive(onNext: { order in // どのメニューがタップされたのか
            guard order >= 0 else { return }
            panelMenu.dismiss(animated: true, completion: nil)
            
            if order == 0 {
                self.showNSFWAlert()
            } else {
                self.viewModel?.changeImageNsfwState()
            }
        }).disposed(by: disposeBag)
        
        presentWithSemiModal(panelMenu, animated: true, completion: nil)
    }
    
    private func showNSFWAlert() {
        let alert = UIAlertController(title: "投稿NSFWの設定", message: "開発中です。", preferredStyle: UIAlertController.Style.alert)
        let cancelAction = UIAlertAction(title: "閉じる", style: UIAlertAction.Style.cancel, handler: nil)
        
        alert.addAction(cancelAction)
        present(alert, animated: true, completion: nil)
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
        
        // 15: 微調整
        mainTextViewBottomConstraint.constant = bottomStackView.frame.height + keyboardHeight - getSafeAreaSize().height + 15
    }
    
    // MARK: Utilities
    
    private func change2AwesomeFont(buttons: [UIBarButtonItem]) {
        buttons.forEach { button in
            button.setTitleTextAttributes([NSAttributedString.Key.font: UIFont.awesomeSolid(fontSize: 17.0)!], for: .normal)
            button.setTitleTextAttributes([NSAttributedString.Key.font: UIFont.awesomeSolid(fontSize: 17.0)!], for: .selected)
        }
    }
    
    private func pickImage(type: UIImagePickerController.SourceType) {
        if UIImagePickerController.isSourceTypeAvailable(.savedPhotosAlbum) {
            let picker = UIImagePickerController()
            picker.sourceType = type
            picker.mediaTypes = UIImagePickerController.availableMediaTypes(for: type) ?? []
            picker.videoQuality = .typeHigh
            picker.delegate = self
            
            presentOnFullScreen(picker, animated: true, completion: nil)
        }
    }
    
    // MARK: Delegate
    
    func textViewDidBeginEditing(_ textView: UITextView) {
        if mainTextView.textColor == .lightGray {
            mainTextView.text = ""
            mainTextView.textColor = .black
        }
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        if mainTextView.text == "" {
            mainTextView.text = "What's happening?"
            mainTextView.textColor = .lightGray
        }
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true, completion: nil)
        
        let isImage = info[UIImagePickerController.InfoKey.originalImage] is UIImage
        
        if isImage {
            guard let originalImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage else { return }
            
            showPhotoEditor(with: originalImage).subscribe(onNext: { editedImage in // 画像エディタを表示
                guard let editedImage = editedImage else { return }
                self.viewModel?.stackFile(original: originalImage, edited: editedImage)
            }).disposed(by: disposeBag)
            
            return
        }
        // is Video
        guard let url = info[UIImagePickerController.InfoKey.mediaURL] as? NSURL else { return }
        AVAsset.convert2Mp4(videoUrl: url) { session in // 動画のデフォルトがmovなのでmp4に変換する
            guard session.status == .completed, let filePath = session.outputURL else { return }
            self.viewModel?.stackFile(videoUrl: filePath)
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
