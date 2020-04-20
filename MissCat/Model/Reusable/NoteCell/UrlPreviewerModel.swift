//
//  UrlPreviewerModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/07.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import SwiftLinkPreview

class UrlPreviewerModel {
    func getPreview(of url: String, handler: @escaping (Response) -> Void) {
        if let cache = Cache.shared.getUrlPreview(on: url) {
            DispatchQueue.main.async { handler(cache) }
            return
        }
        
        let slp = SwiftLinkPreview(session: URLSession.shared,
                                   workQueue: DispatchQueue.global(),
                                   responseQueue: DispatchQueue.main)
        
        slp.preview(url, onSuccess: { res in
            Cache.shared.saveUrlPreview(response: res, on: url)
            handler(res)
        }, onError: handleError)
    }
    
    private func handleError(_ error: PreviewError) {}
}
