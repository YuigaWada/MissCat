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
        let slp = SwiftLinkPreview(session: URLSession.shared,
                                   workQueue: DispatchQueue.global(),
                                   responseQueue: DispatchQueue.main)
        
        slp.preview(url, onSuccess: handler, onError: handleError)
    }
    
    private func handleError(_ error: PreviewError) {}
}
