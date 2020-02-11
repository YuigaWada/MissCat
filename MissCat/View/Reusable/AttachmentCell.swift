//
//  AttachmentCell.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/12/20.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import RxCocoa
import RxSwift
import UIKit

class AttachmentCell: UICollectionViewCell {
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var discardButton: UIButton!
    
    let tapGesture = UITapGestureRecognizer()
    public lazy var tappedImage: Observable<String> = {
        Observable.create { observer in
            
            self.imageView.setTapGesture(self.disposeBag) {
                observer.onNext(self.id)
            }
            
            return Disposables.create()
        }
    }()
    
    public lazy var tappedDiscardButton: Observable<String> = {
        Observable.create { observer in
            
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
        
        setupComponent()
    }
    
    public func setupComponent() {
        contentMode = .left
        
        // imageView / discardButtonの上にcontentViewが掛かっているのでUserInteractionをfalseにする
        contentView.isUserInteractionEnabled = false
        
        // self.layer
        layer.cornerRadius = 5
        imageView.layer.cornerRadius = 5
        
        // discardButton
        discardButton.titleLabel?.font = .awesomeSolid(fontSize: 15.0)
        
        discardButton.layoutIfNeeded()
        discardButton.layer.cornerRadius = discardButton.frame.width / 2
        
        // imageView
        guard let image = imageView.image else { return }
        if frame.size.width > image.size.width || frame.size.height > image.size.height {
            imageView.contentMode = .scaleAspectFill
        } else {
            imageView.contentMode = .center
        }
    }
    
    public func setupCell(_ attachment: PostViewController.Attachments) -> AttachmentCell {
        imageView.image = attachment.image
        id = attachment.id
        
        return self
    }
}
