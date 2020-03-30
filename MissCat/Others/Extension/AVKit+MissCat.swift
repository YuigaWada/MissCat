//
//  AVKit+MissCat.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/06.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import AVKit

extension AVAsset {
    ///  mov→mp4へと変換する
    /// - Parameters:
    ///   - videoUrl: 動画のurl
    ///   - completion:  completion
    static func convert2Mp4(videoUrl: NSURL, completion: @escaping (_ session: AVAssetExportSession) -> Void) {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentationDirectory, .userDomainMask, true)[0] as String
        let fileName = UUID().uuidString + ".mp4"
        let tempPath = documentsPath + fileName
        
        guard let tempUrl = (NSURL.fileURL(withPath: tempPath) as NSURL).absoluteURL else { return } // 一時的にデータを保存
        do {
            try FileManager.default.removeItem(at: tempUrl) // ファイルがすでに存在していれば削除
        } catch {}
        
        guard let exportSession = AVAssetExportSession(asset: AVURLAsset(url: videoUrl as URL, options: nil),
                                                       presetName: AVAssetExportPresetPassthrough) else { return }
        
        exportSession.outputURL = tempUrl
        exportSession.outputFileType = AVFileType.mp4
        exportSession.exportAsynchronously(completionHandler: { () -> Void in
            completion(exportSession)
        })
    }
    
    /// 動画からサムネイルを取得する
    /// - Parameter url: 動画のPath
    static func generateThumbnail(videoFrom url: URL) -> UIImage {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        var time = asset.duration
        time.value = min(time.value, 2)
        do {
            let imageRef = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: imageRef)
        } catch {
            return .init()
        }
    }
}
