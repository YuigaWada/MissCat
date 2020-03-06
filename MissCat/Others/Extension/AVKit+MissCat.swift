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
    public static func convert2Mp4(videoUrl: NSURL, completion: @escaping (_ session: AVAssetExportSession) -> Void) {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentationDirectory, .userDomainMask, true)[0] as String
        let fileName = UUID().uuidString + ".mp4"
        let tempPath = documentsPath + fileName
        
        guard let tempUrl = (NSURL.fileURL(withPath: tempPath) as NSURL).absoluteURL else { return } // 一時的にデータを保存
        do {
            try FileManager.default.removeItem(at: tempUrl) // ファイルがすでに存在していれば削除
        }
        catch { }
        
        guard let exportSession = AVAssetExportSession(asset: AVURLAsset(url: tempUrl, options: nil),
                                                       presetName: AVAssetExportPresetPassthrough) else { return }
        
        exportSession.outputURL = tempUrl
        exportSession.outputFileType = AVFileType.mp4
        exportSession.exportAsynchronously(completionHandler: {() -> Void in
            completion(exportSession)
        })
    }
    
}
