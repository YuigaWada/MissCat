//
//  PostViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/21.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import AVKit
import MisskeyKit
import RxCocoa
import RxSwift

class PostViewModel: ViewModelType {
    struct Input {
        let type: PostViewController.PostType
        let targetNote: NoteCell.Model?
    }
    
    struct Output {
        let iconImage: Driver<UIImage>
        let isSuccess: Driver<Bool>
        
        let attachments: PublishSubject<[PostViewController.AttachmentsSection]>
    }
    
    struct State {}
    
    private var input: Input
    lazy var output: Output = .init(iconImage: self.iconImage.asDriver(onErrorJustReturn: UIImage()),
                                    isSuccess: self.isSuccess.asDriver(onErrorJustReturn: false),
                                    attachments: self.attachments)
    
    private class AttachmentFile {
        fileprivate let id: String = UUID().uuidString
        fileprivate var order: Int = 0
        
        fileprivate var originalImage: UIImage? // 加工前
        fileprivate var image: UIImage? // 加工後
        
        fileprivate var videoPath: URL?
        fileprivate var videoThumbnail: UIImage?
        fileprivate var nsfw: Bool = false
        fileprivate var isVideo: Bool { return videoPath != nil }
        
        init(originalImage: UIImage, image: UIImage, order: Int) {
            self.image = image
            self.originalImage = originalImage
            
            self.order = order
        }
        
        init(videoPath: URL) {
            self.videoPath = videoPath
            videoThumbnail = AVAsset.generateThumbnail(videoFrom: videoPath)
        }
        
        func changeNsfwState(_ nsfw: Bool) -> AttachmentFile {
            self.nsfw = nsfw
            return self
        }
    }
    
    private var iconImage: PublishSubject<UIImage> = .init()
    private var isSuccess: PublishSubject<Bool> = .init()
    
    private var attachmentsLists: [PostViewController.Attachments] = []
    private let attachments: PublishSubject<[PostViewController.AttachmentsSection]> = .init()
    
    private let model = PostModel()
    private var disposeBag: DisposeBag
    private var attachmentFiles: [AttachmentFile] = []
    private var hasVideoAttachment: Bool = false // 写真と動画は共存させないようにする。尚、写真は4枚まで追加可能だが動画は一つのみとする。
    private var isNsfw: Bool {
        guard attachmentFiles.count > 0 else { return false }
        return attachmentFiles[0].nsfw
    }
    
    init(with input: Input, and disposeBag: DisposeBag) {
        self.input = input
        self.disposeBag = disposeBag
        
        model.getIconImage { image in
            guard let image = image else { return }
            self.iconImage.onNext(image)
        }
    }
    
    // MARK: Publics
    
    func submitNote(_ note: String) {
        let renoteId = input.type == .CommentRenote ? input.targetNote?.noteId : nil
        let replyId = input.type == .Reply ? input.targetNote?.noteId : nil
        
        guard attachmentFiles.count > 0 else {
            model.submitNote(note, fileIds: nil, replyId: replyId, renoteId: renoteId) { self.isSuccess.onNext($0) }
            return
        }
        
        uploadFiles { fileIds in
            self.model.submitNote(note, fileIds: fileIds, replyId: replyId, renoteId: renoteId) { self.isSuccess.onNext($0) }
        }
    }
    
    func getLocation() {}
    
    func uploadFiles(completion: @escaping ([String]) -> Void) {
        if hasVideoAttachment {
            uploadVideo(completion: completion)
        } else {
            uploadImages(completion: completion)
        }
    }
    
    // 画像をスタックさせておいて、アップロードは直前に
    func stackFile(original: UIImage, edited: UIImage) {
        guard !hasVideoAttachment else { return } // 写真と動画は共存させないように
        let targetImage = AttachmentFile(originalImage: original, image: edited, order: attachmentFiles.count + 1)
        
        attachmentFiles.append(targetImage)
        addAttachmentView(targetImage)
    }
    
    func stackFile(videoUrl: URL) {
        guard attachmentFiles.count == 0 else { return } // 動画は1つまで
        let targetVideo = AttachmentFile(videoPath: videoUrl)
        
        attachmentFiles.append(targetVideo)
        
        addAttachmentView(targetVideo)
        hasVideoAttachment = true
    }
    
    func updateFile(id: String, edited: UIImage) {
        guard !hasVideoAttachment else { return } // 写真と動画は共存させないように
        
        attachmentFiles.filter { $0.id == id }.forEach { $0.image = edited }
    }
    
    func removeAttachmentView(_ id: String) {
        for index in 0 ..< attachmentsLists.count {
            let attachment = attachmentsLists[index]
            
            if attachment.id == id {
                attachmentsLists.remove(at: index)
                break
            }
        }
        
        attachments.onNext([PostViewController.AttachmentsSection(items: attachmentsLists)])
    }
    
    func changeImageNsfwState() {
        let currentState = isNsfw
        attachmentFiles = attachmentFiles.map { $0.changeNsfwState(!currentState) }
        attachmentsLists = attachmentsLists.map { $0.changeNsfwState(!currentState) }
        
        attachments.onNext([PostViewController.AttachmentsSection(items: attachmentsLists)])
    }
    
    // MARK: Privates
    
    private func uploadImages(completion: @escaping ([String]) -> Void) {
        var fileIds: [String] = []
        attachmentFiles.forEach { image in
            guard let image = image.image else { return }
            
            self.model.uploadFile(image, nsfw: isNsfw) { fileId in
                guard let fileId = fileId else { return }
                fileIds.append(fileId)
                
                if fileIds.count == self.attachmentFiles.count { completion(fileIds) }
            }
        }
    }
    
    private func uploadVideo(completion: @escaping ([String]) -> Void) {
        guard attachmentFiles.count == 1 else { return }
        
        var fileIds: [String] = []
        let videoAttachment = attachmentFiles[0]
        guard let path = videoAttachment.videoPath, let video = getVideoData(from: path) else { return }
        
        model.uploadFile(video, nsfw: isNsfw) { fileId in
            guard let fileId = fileId else { return }
            fileIds.append(fileId)
            
            if fileIds.count == self.attachmentFiles.count { completion(fileIds) }
        }
    }
    
    private func addAttachmentView(_ attachment: AttachmentFile) {
        var item: PostViewController.Attachments
        if attachment.isVideo {
            guard let thumbnail = attachment.videoThumbnail else { return }
            item = .init(id: attachment.id, image: thumbnail, type: .Video)
        } else {
            guard let originalImage = attachment.originalImage else { return }
            item = .init(id: attachment.id, image: originalImage, type: .Image)
        }
        
        attachmentsLists.append(item)
        attachments.onNext([PostViewController.AttachmentsSection(items: attachmentsLists)])
    }
    
    private func getVideoData(from path: URL) -> Data? {
        do {
            return try Data(contentsOf: path)
        } catch {
            return nil
        }
    }
}
