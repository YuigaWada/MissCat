//
//  PostViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/21.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit
import iOSPhotoEditor
import RxSwift
import RxDataSources

public typealias AttachmentsDataSource = RxCollectionViewSectionedReloadDataSource<PostViewController.AttachmentsSection>
public class PostViewController: UIViewController, UITextViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UICollectionViewDelegate {
    
    @IBOutlet weak var attachmentCollectionView: UICollectionView!
    
    @IBOutlet weak var cancelButton: UIButton!
    @IBOutlet weak var submitButton: UIButton!
    @IBOutlet weak var iconImageView: UIImageView!
    @IBOutlet weak var mainTextView: UITextView!
    @IBOutlet weak var mainTextViewBottomConstraint: NSLayoutConstraint!
    
    @IBOutlet weak var bottomStackView: UIStackView!
    
    private lazy var viewModel = PostViewModel(disposeBag: disposeBag)
    private lazy var toolBar = UIToolbar()
    private let disposeBag = DisposeBag()
    
    
    private lazy var counter = UIBarButtonItem(title: "1500", style: .done, target: self, action:nil)
    
    //MARK: Life Cycle
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        let dataSource = self.setupDataSource()
        self.binding(dataSource)
        
        self.setupCollectionView()
        self.setupTextView()
        self.setupNavItem()
        
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
        self.mainTextView.becomeFirstResponder()
    }
    
    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        self.iconImageView.layer.cornerRadius = self.iconImageView.frame.width / 2
    }
    
    //MARK: Setup
    
    private func setupDataSource()-> AttachmentsDataSource {
        let dataSource = AttachmentsDataSource(
            configureCell: { dataSource, tableView, indexPath, item in
                return self.setupCell(dataSource, self.attachmentCollectionView, indexPath)
        })
        
        return dataSource
    }
    
    
    private func binding(_ dataSource: AttachmentsDataSource) {
        let output = viewModel.output
        
        output.iconImage.drive(self.iconImageView.rx.image).disposed(by: disposeBag)
        //        output.isSuccess.subscribe { _ in
        //
        //        }.disposed(by: disposeBag)
        
        
        self.cancelButton.rx.tap.asObservable().subscribe{ _ in
            self.mainTextView.resignFirstResponder()
            self.dismiss(animated: true, completion: nil)
        }.disposed(by: disposeBag)
        
        self.submitButton.rx.tap.asObservable().subscribe { _ in
            self.viewModel.submitNote(self.mainTextView.text)
            DispatchQueue.main.async { self.dismiss(animated: true, completion: nil) }
        }.disposed(by: disposeBag)
        
        self.mainTextView.rx.text.asObservable().map{
            guard let text = $0 else { return $0 ?? "" }
            return String(1500 - text.count)
        }.bind(to: self.counter.rx.title).disposed(by: disposeBag)
        
        output.attachments.bind(to: self.attachmentCollectionView.rx.items(dataSource: dataSource)).disposed(by: disposeBag)
    }
    
    
    private func setupCollectionView() {
        self.attachmentCollectionView.register(UINib(nibName: "AttachmentCell", bundle: nil), forCellWithReuseIdentifier: "AttachmentCell")
        self.attachmentCollectionView.rx.setDelegate(self).disposed(by: disposeBag)
        
        let flowLayout = UICollectionViewFlowLayout()
        let size = self.view.frame.width / 3
        
        flowLayout.itemSize = CGSize(width: size, height: self.attachmentCollectionView.frame.height)
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        self.attachmentCollectionView.collectionViewLayout = flowLayout
    }
    
    private func setupTextView() {
        //miscs
        self.mainTextView.rx.setDelegate(self).disposed(by: disposeBag)
        self.mainTextView.textColor = .lightGray
        
        
        //above toolbar
        let flexibleItem = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        let cameraButton = UIBarButtonItem(title: "camera", style: .plain, target: self, action: nil)
        let imageButton = UIBarButtonItem(title: "images", style: .plain, target: self, action: nil)
        let pollButton = UIBarButtonItem(title: "poll", style: .plain, target: self, action:nil)
        let locationButton = UIBarButtonItem(title: "map-marker-alt", style: .plain, target: self, action:nil)
        
        
        self.counter.setTitleTextAttributes([NSAttributedString.Key.font: UIFont(name: "Helvetica", size: 14.0)!], for: .normal)
        self.counter.setTitleTextAttributes([NSAttributedString.Key.font: UIFont(name: "Helvetica", size: 14.0)!], for: .selected)
        
        cameraButton.rx.tap.subscribe{ _ in self.pickImage(type: .camera) }.disposed(by: disposeBag)
        imageButton.rx.tap.subscribe{ _ in self.pickImage(type: .photoLibrary) }.disposed(by: disposeBag)
        pollButton.rx.tap.subscribe{ _ in  }.disposed(by: disposeBag)
        locationButton.rx.tap.subscribe{ _ in self.viewModel.getLocation() }.disposed(by: disposeBag)
        
        self.toolBar.setItems([cameraButton, imageButton, pollButton, locationButton,
                               flexibleItem, flexibleItem,
                               counter], animated: true)
        self.toolBar.sizeToFit()
        
        self.change2AwesomeFont(buttons: [cameraButton, imageButton, pollButton, locationButton])
        self.mainTextView.inputAccessoryView = self.toolBar
    }
    
    private func setupNavItem() {
        let fontSize: CGFloat = 17.0
        
        self.cancelButton.titleLabel?.font = .awesomeSolid(fontSize: fontSize)
        self.submitButton.titleLabel?.font = .awesomeSolid(fontSize: fontSize)
    }
    
    private func setupCell(_ dataSource: CollectionViewSectionedDataSource<PostViewController.AttachmentsSection>, _ collectionView: UICollectionView, _ indexPath: IndexPath)-> UICollectionViewCell {
        let index = indexPath.row
        let item = dataSource.sectionModels[0].items[index]
        
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "AttachmentCell", for: indexPath) as? AttachmentCell else {fatalError("Internal Error.")}
        
        
        cell.tappedImage.subscribe{ id in
            guard item.id == id.element else { return }
            
            self.showPhotoEditor(with: item.image).subscribe(onNext: { editedImage in // 画像エディタを表示
                guard let editedImage = editedImage else { return }
                self.viewModel.stackFile(original: item.image, edited: editedImage)
                
            }).disposed(by: self.disposeBag)
            
        }.disposed(by: disposeBag)
        
        cell.tappedDiscardButton.subscribe{ id in
            
        }.disposed(by: disposeBag)
        
        return cell.setupCell(item)
    }
    
    
    //キーボードの高さに合わせてcomponentの高さを調整する
    private func fitToKeyboard(keyboardHeight: CGFloat) {
        self.layoutIfNeeded(to: [self.bottomStackView, self.toolBar])
        
        
        self.mainTextViewBottomConstraint.constant = self.bottomStackView.frame.height + keyboardHeight - self.getSafeAreaSize().height
        
    }
    
    
    
    //MARK: Utilities
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
            picker.delegate = self
            
            self.presentOnFullScreen(picker, animated: true, completion: nil)
        }
    }
    
    //MARK: Delegate
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
    
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        
        picker.dismiss(animated: true, completion: nil)
        guard let originalImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage else { return }
        
        self.showPhotoEditor(with: originalImage).subscribe(onNext: { editedImage in // 画像エディタを表示
            guard let editedImage = editedImage else { return }
            self.viewModel.stackFile(original: originalImage, edited: editedImage)
        }).disposed(by: disposeBag)
        
    }
    
    //MARK: NotificationCenter
    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let userInfo = notification.userInfo as? [String: Any],
            let keyboardInfo = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
        
        let keyboardSize = keyboardInfo.cgRectValue.size
        self.fitToKeyboard(keyboardHeight: keyboardSize.height)
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
