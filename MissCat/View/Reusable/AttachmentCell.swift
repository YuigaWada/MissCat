//
//  AttachmentCell.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/12/20.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit
import RxCocoa
import RxSwift

class AttachmentCell: UICollectionViewCell {
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var discardButton: UIButton!
    
    let tapGesture = UITapGestureRecognizer()
    public lazy var tappedImage: Observable<String> = {
        return Observable.create { observer in
            
            self.imageView.setTapGesture(self.disposeBag) {
                observer.onNext(self.id)
            }
            
            return Disposables.create()
        }
    }()
    
    public lazy var tappedDiscardButton: Observable<String> = {
        return Observable.create { observer in
            
            self.discardButton.rx.tap.subscribe { _ in
                observer.onNext(self.id)
            }.disposed(by: self.disposeBag)
            
            return Disposables.create()
        }
    }()
    
    private var disposeBag: DisposeBag = .init()
    private var id: String = ""
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        self.setupComponent()
    }
    
    public func setupComponent() {
        
        self.contentMode = .left
        
         // imageView / discardButtonの上にcontentViewが掛かっているのでUserInteractionをfalseにする
        self.contentView.isUserInteractionEnabled = false
        
        //self.layer
        self.layer.cornerRadius = 5
        self.imageView.layer.cornerRadius = 5
        
        
        //discardButton
        self.discardButton.titleLabel?.font = .awesomeSolid(fontSize: 15.0)
        
        discardButton.layoutIfNeeded()
        discardButton.layer.cornerRadius = discardButton.frame.width / 2
        
        //imageView
        guard let image = imageView.image else { return }
        if self.frame.size.width > image.size.width || self.frame.size.height > image.size.height {
            self.imageView.contentMode = .scaleAspectFill
        }
        else {
            self.imageView.contentMode = .center
        }
            
    }
    
    public func setupCell(_ attachment: PostViewController.Attachments)-> AttachmentCell {
        self.imageView.image = attachment.image
        self.id = attachment.id
        
        return self
    }
    
}

