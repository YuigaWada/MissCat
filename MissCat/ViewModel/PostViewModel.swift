//
//  PostViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/21.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxSwift

public class PostViewModel {
    
    private struct AttachmentImage {
        fileprivate let id: String = UUID().uuidString
        fileprivate var order: Int = 0
        fileprivate var image: UIImage?
        
        init(image: UIImage, order: Int) {
            self.image = image
            self.order = order
        }
    }
    
    public var iconImage: PublishSubject<UIImage> = .init()
    public var isSuccess: PublishSubject<Bool> = .init()
    
    private let model = PostModel()
    private var disposeBag: DisposeBag
    private var attachmentImages: [AttachmentImage] = []
    
    init(disposeBag: DisposeBag) {
        self.disposeBag = disposeBag
        
        model.getIconImage { image in
            guard let image = image else { return }
            self.iconImage.onNext(image)
        }
    }
    
    public func submitNote(_ note: String) {
        guard self.attachmentImages.count > 0 else {
            self.model.submitNote(note, fileIds: nil){ self.isSuccess.onNext($0) }
            return 
        }
        
        self.uploadFiles { fileIds in
            self.model.submitNote(note, fileIds: fileIds){ self.isSuccess.onNext($0) }
        }
    }
    
    public func getLocation() {
        
    }
    
    
    
    public func uploadFiles(completion: @escaping ([String])->()) {
        var fileIds: [String] = []
        
        attachmentImages.forEach{ image in
            guard let image = image.image else { return }
            
            self.model.uploadFile(image) { fileId in
                guard let fileId = fileId else { return }
                fileIds.append(fileId)
                
                if fileIds.count == self.attachmentImages.count { completion(fileIds) }
            }
        }
        
    }
    
    //画像をスタックさせておいて、アップロードは直前に
    public func stackFile(_ image: UIImage) {
        let targetImage = AttachmentImage(image: image, order: self.attachmentImages.count + 1)
        
        self.attachmentImages.append(targetImage)
    }
    
}
