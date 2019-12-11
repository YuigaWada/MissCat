//
//  PostModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/21.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit

public class PostModel {
    
    private var iconImage: UIImage?
    
    public func getIconImage(completion: @escaping (UIImage?)->()) {
        if let iconImage = iconImage {
            completion(iconImage)
            return
        }
        
        Cache.shared.getMe { me in
            guard let me = me, let iconUrl = me.avatarUrl else { completion(nil); return }
            
            iconUrl.toUIImage{ image in
                self.iconImage = image
                completion(image)
            }
        }
    }
    
    
    public func submitNote(_ note: String?, fileIds: [String]? = nil, completion: @escaping (Bool)->()) {
        guard let note = note else { return }
        
        MisskeyKit.notes.createNote(text: note, fileIds: fileIds ?? []) { post, error in
            let isSuccess = post != nil && error == nil
            completion(isSuccess)
        }
    }
    
    public func uploadFile(_ image: UIImage, completion: @escaping (String?)->()) {
        guard let resizedImage = image.resized(widthUnder: 1024), let targetImage = resizedImage.jpegData(compressionQuality: 0.5) else { return }
        
        MisskeyKit.drive.createFile(fileData: targetImage, fileType: "image/jpeg", name: UUID().uuidString + ".jpeg", isSensitive: false, force: false) { result, error in
            guard let result = result, error == nil else { return }
            
            completion(result.id)
        }
        
    }
    
}
