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

public class PostViewController: UIViewController, UITextViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    @IBOutlet weak var attachmentCollectionView: UICollectionView!
    
    @IBOutlet weak var cancelButton: UIButton!
    @IBOutlet weak var submitButton: UIButton!
    @IBOutlet weak var iconImageView: UIImageView!
    @IBOutlet weak var mainTextView: UITextView!
    @IBOutlet weak var mainTextViewBottomConstraint: NSLayoutConstraint!
    
    private lazy var viewModel = PostViewModel(disposeBag: disposeBag)
    private let disposeBag = DisposeBag()

    
    private lazy var counter = UIBarButtonItem(title: "1500", style: .done, target: self, action:nil)
    
    //MARK: Life Cycle
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        self.binding()
        self.setupTextView()
        self.setupNavItem()
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
    private func binding() {
        viewModel.iconImage.bind(to: self.iconImageView.rx.image).disposed(by: disposeBag)
        viewModel.isSuccess.subscribe { _ in
            
        }.disposed(by: disposeBag)
        
        
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

    }
    
    
    private func setupTextView() {
        //miscs
        self.mainTextView.rx.setDelegate(self).disposed(by: disposeBag)
        self.mainTextView.textColor = .lightGray
        
        
        //above toolbar
        let toolBar = UIToolbar()
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
        
        toolBar.setItems([cameraButton, imageButton, pollButton, locationButton,
                          flexibleItem, flexibleItem,
                          counter], animated: true)
        toolBar.sizeToFit()
        
        self.change2AwesomeFont(buttons: [cameraButton, imageButton, pollButton, locationButton])
        self.mainTextView.inputAccessoryView = toolBar
    }
    
    private func setupNavItem() {
        let fontSize: CGFloat = 17.0
        
        self.cancelButton.titleLabel?.font = .awesomeSolid(fontSize: fontSize)
        self.submitButton.titleLabel?.font = .awesomeSolid(fontSize: fontSize)
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
        
            self.present(picker, animated: true, completion: nil)
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
        guard let image = info[UIImagePickerController.InfoKey.originalImage] as? UIImage else { return }
        
        self.showPhotoEditor(with: image).subscribe(onNext: { editedImage in // 画像エディタを表示
            guard let editedImage = editedImage else { return }
            self.viewModel.stackFile(editedImage)
        }).disposed(by: disposeBag)
        
    }
}
