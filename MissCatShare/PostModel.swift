//
//  PostModel.swift
//  MissCatShare
//
//  Created by Yuiga Wada on 2020/08/07.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit

class PostModel {
    private let misskey: MisskeyKit?
    
    init(user: SecureUser) {
        let misskey = MisskeyKit()
        misskey.changeInstance(instance: user.instance)
        misskey.auth.setAPIKey(user.apiKey!)
        self.misskey = misskey
    }
    
    /// 投稿する
    func submitNote(_ note: String?, cw: String? = nil, fileIds: [String]? = nil, replyId: String? = nil, renoteId: String? = nil, visibility: Visibility, completion: @escaping (Bool) -> Void) {
        guard let note = note else { return }
        
        if let renoteId = renoteId { // 引用RN
            misskey?.notes.renote(renoteId: renoteId, quote: note, visibility: visibility) { post, error in
                let isSuccess = post != nil && error == nil
                completion(isSuccess)
            }
        } else { // 通常の投稿
            misskey?.notes.createNote(visibility: visibility, text: note, cw: cw ?? "", fileIds: fileIds ?? [], replyId: replyId ?? "") { post, error in
                let isSuccess = post != nil && error == nil
                completion(isSuccess)
            }
        }
    }
    
    /// 画像ファイルをアップデートする
    func uploadFile(_ image: UIImage, nsfw: Bool, completion: @escaping (String?) -> Void) {
        guard let resizedImage = image.resized(widthUnder: 1024), let targetImage = resizedImage.jpegData(compressionQuality: 0.5) else { return }
        
        misskey?.drive.createFile(fileData: targetImage, fileType: "image/jpeg", name: UUID().uuidString + ".jpeg", isSensitive: nsfw, force: false) { result, error in
            guard let result = result, error == nil else { return }
            
            completion(result.id)
        }
    }
    
    /// 動画ファイルをアップロードする
    func uploadFile(_ videoData: Data, nsfw: Bool, completion: @escaping (String?) -> Void) {
        misskey?.drive.createFile(fileData: videoData, fileType: "video/mp4", name: UUID().uuidString + ".mp4", isSensitive: nsfw, force: false) { result, error in
            guard let result = result, error == nil else { return }
            
            completion(result.id)
        }
    }
}

extension UIImage {
    func resized(widthUnder: CGFloat) -> UIImage? {
        return resized(withPercentage: widthUnder / size.width)
    }
    
    func resized(withPercentage percentage: CGFloat) -> UIImage? {
        let canvasSize = CGSize(width: size.width * percentage, height: size.height * percentage)
        UIGraphicsBeginImageContextWithOptions(canvasSize, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: canvasSize))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    func resizedTo5MB() -> UIImage? {
        guard let imageData = pngData() else { return nil }
        
        var resizingImage = self
        var imageSizeKB = Double(imageData.count) / 1000.0 // ! Or devide for 1024 if you need KB but not kB
        
        while imageSizeKB > 5000 { // ! Or use 1024 if you need KB but not kB
            guard let resizedImage = resizingImage.resized(withPercentage: 0.9),
                let imageData = resizedImage.pngData()
            else { return nil }
            
            resizingImage = resizedImage
            imageSizeKB = Double(imageData.count) / 1000.0 // ! Or devide for 1024 if you need KB but not kB
        }
        
        return resizingImage
    }
}
