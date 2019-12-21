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
    
    public lazy var tappedImage: PublishRelay<String> = {
        let relay: PublishRelay<String> = .init()
        imageView.setTapGesture(self.disposeBag) { relay.accept(self.id) }
        
        return relay
    }()
    
    public lazy var tappedDiscardButton: PublishRelay<String> = {
        let relay: PublishRelay<String> = .init()
        discardButton.setTapGesture(self.disposeBag) { relay.accept(self.id) }
        
        return relay
    }()
    
    private var disposeBag: DisposeBag = .init()
    private var id: String = ""
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        self.setupComponent()
    }
    
    public func setupComponent() {
        
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

