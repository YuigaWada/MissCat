//
//  ProfileSettingsModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/05/15.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxSwift

class ProfileSettingsModel {
    func save(diff: ProfileSettingsViewModel.Changed) {
        guard diff.hasChanged else { return }
        uploadImage(diff.banner) { bannerId in
            self.uploadImage(diff.icon) { avatarId in
                self.updateProfile(with: diff, avatarId: avatarId, bannerId: bannerId)
            }
        }
    }
    
    private func updateProfile(with diff: ProfileSettingsViewModel.Changed, avatarId: String?, bannerId: String?) {
        MisskeyKit.users.updateMyAccount(name: diff.name ?? "", description: diff.description ?? "", avatarId: avatarId ?? "", bannerId: bannerId ?? "", isCat: diff.isCat ?? nil) { res, error in
            guard let res = res, error == nil else { return }
            print(res)
        }
    }
    
    private func uploadImage(_ image: UIImage?, completion: @escaping (String?) -> Void) {
        guard let image = image,
            let resizedImage = image.resized(widthUnder: 1024),
            let targetImage = resizedImage.jpegData(compressionQuality: 0.5) else { completion(nil); return }
        
        MisskeyKit.drive.createFile(fileData: targetImage, fileType: "image/jpeg", name: UUID().uuidString + ".jpeg", force: false) { result, error in
            guard let result = result, error == nil else { return }
            completion(result.id)
        }
    }
}
