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
    private let misskey: MisskeyKit?
    init(from misskey: MisskeyKit?) {
        self.misskey = misskey
    }
    
    /// プロフィールの差分をMisskeyへ伝達する
    /// - Parameter diff: 差分
    func save(diff: ChangedProfile) {
        guard diff.hasChanged else { return }
        uploadImage(diff.banner) { bannerId in
            self.uploadImage(diff.icon) { avatarId in
                self.updateProfile(with: diff, avatarId: avatarId, bannerId: bannerId)
            }
        }
    }
    
    /// "i/update"を叩く
    private func updateProfile(with diff: ChangedProfile, avatarId: String?, bannerId: String?) {
        misskey?.users.updateMyAccount(name: diff.name ?? "", description: diff.description ?? "", avatarId: avatarId ?? "", bannerId: bannerId ?? "", isCat: diff.isCat ?? nil) { res, error in
            guard let res = res, error == nil else { return }
            print(res)
        }
    }
    
    /// 画像をdriveへとアップロードする
    private func uploadImage(_ image: UIImage?, completion: @escaping (String?) -> Void) {
        guard let image = image,
            let resizedImage = image.resized(widthUnder: 1024),
            let targetImage = resizedImage.jpegData(compressionQuality: 0.5) else { completion(nil); return }
        
        misskey?.drive.createFile(fileData: targetImage, fileType: "image/jpeg", name: UUID().uuidString + ".jpeg", force: false) { result, error in
            guard let result = result, error == nil else { return }
            completion(result.id)
        }
    }
}
