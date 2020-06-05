//
//  PostModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/21.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MediaPlayer
import MisskeyKit

class PostModel {
    private var iconImage: UIImage?

    private let misskey: MisskeyKit?
    init(from misskey: MisskeyKit?) {
        self.misskey = misskey
    }
    
    /// 自分のアイコンを取得する
    func getIconImage(completion: @escaping (UIImage?) -> Void) {
        if let iconImage = iconImage {
            completion(iconImage)
            return
        }
        
        self.misskey?.users.i { me, _ in
            guard let me = me, let iconUrl = me.avatarUrl else { completion(nil); return }
            
            _ = iconUrl.toUIImage { image in
                self.iconImage = image
                completion(image)
            }
        }
    }
    
    /// 投稿する
    func submitNote(_ note: String?, cw: String? = nil, fileIds: [String]? = nil, replyId: String? = nil, renoteId: String? = nil, visibility: Visibility, completion: @escaping (Bool) -> Void) {
        guard let note = note else { return }
        
        if let renoteId = renoteId { // 引用RN
            self.misskey?.notes.renote(renoteId: renoteId, quote: note, visibility: visibility) { post, error in
                let isSuccess = post != nil && error == nil
                completion(isSuccess)
            }
        } else { // 通常の投稿
            self.misskey?.notes.createNote(visibility: visibility, text: note, cw: cw ?? "", fileIds: fileIds ?? [], replyId: replyId ?? "") { post, error in
                let isSuccess = post != nil && error == nil
                completion(isSuccess)
            }
        }
    }
    
    /// 画像ファイルをアップデートする
    func uploadFile(_ image: UIImage, nsfw: Bool, completion: @escaping (String?) -> Void) {
        guard let resizedImage = image.resized(widthUnder: 1024), let targetImage = resizedImage.jpegData(compressionQuality: 0.5) else { return }
        
        self.misskey?.drive.createFile(fileData: targetImage, fileType: "image/jpeg", name: UUID().uuidString + ".jpeg", isSensitive: nsfw, force: false) { result, error in
            guard let result = result, error == nil else { return }
            
            completion(result.id)
        }
    }
    
    /// 動画ファイルをアップロードする
    func uploadFile(_ videoData: Data, nsfw: Bool, completion: @escaping (String?) -> Void) {
        self.misskey?.drive.createFile(fileData: videoData, fileType: "video/mp4", name: UUID().uuidString + ".mp4", isSensitive: nsfw, force: false) { result, error in
            guard let result = result, error == nil else { return }
            
            completion(result.id)
        }
    }
    
    /// 現在再生している曲についての情報を取得する
    func getNowPlayingInfo() -> NowPlaying? {
        guard let nowPlayingItem = MPMusicPlayerController.systemMusicPlayer.nowPlayingItem else { return nil }
        
        let artwork = nowPlayingItem.artwork?.image(at: CGSize(width: 200, height: 200))
        return .init(artist: nowPlayingItem.artist,
                     title: nowPlayingItem.title ?? "",
                     artwork: artwork)
    }
    
    /// 前に使用した公開範囲を取得する
    func getSavedVisibility() -> Visibility {
        return Cache.UserDefaults.shared.getCurrentVisibility() ?? .public
    }
    
    /// 公開範囲を保存する
    func savedVisibility(_ visibility: Visibility) {
        Cache.UserDefaults.shared.setCurrentVisibility(visibility)
    }
}

extension PostModel {
    struct NowPlaying {
        let artist: String?
        let title: String
        let artwork: UIImage?
    }
}
 
