//
//  PostViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/21.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxCocoa
import RxSwift

class PostViewModel: ViewModelType {
    struct Input {}
    
    struct Output {
        let iconImage: Driver<UIImage>
        let isSuccess: Driver<Bool>
        
        let attachments: PublishSubject<[PostViewController.AttachmentsSection]>
    }
    
    struct State {}
    
    public lazy var output: Output = .init(iconImage: self.iconImage.asDriver(onErrorJustReturn: UIImage()),
                                           isSuccess: self.isSuccess.asDriver(onErrorJustReturn: false),
                                           attachments: self.attachments)
    
    private struct AttachmentImage {
        fileprivate let id: String = UUID().uuidString
        fileprivate var order: Int = 0
        
        fileprivate var originalImage: UIImage
        fileprivate var image: UIImage?
        
        init(originalImage: UIImage, image: UIImage, order: Int) {
            self.image = image
            self.originalImage = originalImage
            
            self.order = order
        }
    }
    
    private var iconImage: PublishSubject<UIImage> = .init()
    private var isSuccess: PublishSubject<Bool> = .init()
    
    private var attachmentsLists: [PostViewController.Attachments] = []
    private let attachments: PublishSubject<[PostViewController.AttachmentsSection]> = .init()
    
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
        guard attachmentImages.count > 0 else {
            model.submitNote(note, fileIds: nil) { self.isSuccess.onNext($0) }
            return
        }
        
        uploadFiles { fileIds in
            self.model.submitNote(note, fileIds: fileIds) { self.isSuccess.onNext($0) }
        }
    }
    
    public func getLocation() {}
    
    public func uploadFiles(completion: @escaping ([String]) -> Void) {
        var fileIds: [String] = []
        
        attachmentImages.forEach { image in
            guard let image = image.image else { return }
            
            self.model.uploadFile(image) { fileId in
                guard let fileId = fileId else { return }
                fileIds.append(fileId)
                
                if fileIds.count == self.attachmentImages.count { completion(fileIds) }
            }
        }
    }
    
    // 画像をスタックさせておいて、アップロードは直前に
    public func stackFile(original: UIImage, edited: UIImage) {
        let targetImage = AttachmentImage(originalImage: original,
                                          image: edited, order: attachmentImages.count + 1)
        
        attachmentImages.append(targetImage)
        
        addAttachmentView(targetImage)
    }
    
    private func addAttachmentView(_ attachment: AttachmentImage) {
        let item = PostViewController.Attachments(image: attachment.originalImage, type: .Image)
        
        attachmentsLists.append(item)
        attachments.onNext([PostViewController.AttachmentsSection(items: attachmentsLists)])
    }
    
    public func removeAttachmentView(_ id: String) {
        for index in 0 ..< attachmentsLists.count {
            let attachment = attachmentsLists[index]
            
            if attachment.id == id {
                attachmentsLists.remove(at: index)
                break
            }
        }
        
        attachments.onNext([PostViewController.AttachmentsSection(items: attachmentsLists)])
    }
}
