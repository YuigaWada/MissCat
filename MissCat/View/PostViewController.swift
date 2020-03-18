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

public typealias AttachmentsDataSource = RxCollectionViewSectionedReloadDataSource<PostViewController.AttachmentsSection>
public class PostViewController: UIViewController, UITextViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UICollectionViewDelegate {
    @IBOutlet weak var attachmentCollectionView: UICollectionView!
    
    @IBOutlet weak var cancelButton: UIButton!
    @IBOutlet weak var submitButton: UIButton!
    @IBOutlet weak var iconImageView: UIImageView!
    
    @IBOutlet weak var mainTextView: UITextView!
    @IBOutlet weak var mainTextViewBottomConstraint: NSLayoutConstraint!
    
    @IBOutlet weak var bottomStackView: UIStackView!
    @IBOutlet weak var addLocationButon: UIButton!
    
    private var postType: PostType = .Post
    private var targetNoteCell: NoteCell?
    
    private lazy var viewModel = PostViewModel(disposeBag: disposeBag)
    private lazy var toolBar = UIToolbar()
    private let disposeBag = DisposeBag()
    
    private lazy var counter = UIBarButtonItem(title: "1500", style: .done, target: self, action: nil)
    
    // MARK: Life Cycle
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        let dataSource = setupDataSource()
        binding(dataSource)
        
        setupCollectionView()
        setupTextView()
        setupNavItem()
        setupTargetNoteCell()
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillShow(_:)),
                                               name: UIResponder.keyboardWillShowNotification,
                                               object: nil)
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        mainTextView.becomeFirstResponder()
    }
    
    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        iconImageView.layer.cornerRadius = iconImageView.frame.width / 2
    }
    
    /// 引用RN / リプライの場合に、対象ノートのモデルを受け渡す
    /// - Parameters:
    ///   - note: note model
    ///   - type: PostType
    public func setTargetNote(_ note: NoteCell.Model, type: PostType) {
        guard let noteCell = UINib(nibName: "NoteCell", bundle: nil).instantiate(withOwner: self, options: nil).first as? NoteCell else { return }
        
        note.onOtherNote = true
        note.files = []
        
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
    
    private func binding(_ dataSource: AttachmentsDataSource) {
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
            self.viewModel.submitNote(self.mainTextView.text)
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
    
    private func setupTextView() {
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
        locationButton.rx.tap.subscribe { _ in self.viewModel.getLocation() }.disposed(by: disposeBag)
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
        
        cell.tappedImage.subscribe { id in
            guard item.id == id.element else { return }
            
            self.showPhotoEditor(with: item.image).subscribe(onNext: { editedImage in // 画像エディタを表示
                guard let editedImage = editedImage else { return }
                self.viewModel.stackFile(original: item.image, edited: editedImage)
                
            }).disposed(by: self.disposeBag)
            
        }.disposed(by: disposeBag)
        
        cell.tappedDiscardButton.subscribe(onNext: { id in
            self.viewModel.removeAttachmentView(id)
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
        }).disposed(by: disposeBag)
        
        presentWithSemiModal(panelMenu, animated: true, completion: nil)
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
            mainTextView.replace(selectedTextRange,
                                 withText: emojiModel.isDefault ? emojiModel.rawEmoji : ":\(emojiModel.rawEmoji):")
        }
    }
    
    // キーボードの高さに合わせてcomponentの高さを調整する
    private func fitToKeyboard(keyboardHeight: CGFloat) {
        layoutIfNeeded(to: [bottomStackView, toolBar])
        
        mainTextViewBottomConstraint.constant = bottomStackView.frame.height + keyboardHeight - getSafeAreaSize().height
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
    
    public func textViewDidBeginEditing(_ textView: UITextView) {
        if mainTextView.textColor == .lightGray {
            mainTextView.text = ""
            mainTextView.textColor = .black
        }
    }
    
    public func textViewDidEndEditing(_ textView: UITextView) {
        if mainTextView.text == "" {
            mainTextView.text = "What's happening?"
            mainTextView.textColor = .lightGray
        }
    }
    
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true, completion: nil)
        
        let isImage = info[UIImagePickerController.InfoKey.originalImage] is UIImage
        
        if isImage {
            guard let originalImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage else { return }
            
            showPhotoEditor(with: originalImage).subscribe(onNext: { editedImage in // 画像エディタを表示
                guard let editedImage = editedImage else { return }
                self.viewModel.stackFile(original: originalImage, edited: editedImage)
            }).disposed(by: disposeBag)
            
            return
        }
        // is Video
        guard let url = info[UIImagePickerController.InfoKey.mediaURL] as? NSURL else { return }
        AVAsset.convert2Mp4(videoUrl: url) { session in // 動画のデフォルトがmovなのでmp4に変換する
            guard session.status == .completed, let filePath = session.outputURL else { return }
            self.viewModel.stackFile(videoUrl: filePath)
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

public extension PostViewController {
    enum PostType {
        case Post
        case Reply
        case CommentRenote
    }
}

public extension PostViewController {
    struct AttachmentsSection {
        public var items: [Item]
    }
    
    struct Attachments {
        public var id: String = UUID().uuidString
        
        public var image: UIImage
        public var type: Type
    }
    
    enum `Type` {
        case Image
        case Video
    }
}

extension PostViewController.AttachmentsSection: SectionModelType {
    public typealias Item = PostViewController.Attachments
    
    public init(original: PostViewController.AttachmentsSection, items: [Item]) {
        self = original
        self.items = items
    }
}
