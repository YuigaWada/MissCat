//
//  UrlPreviewerModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/07.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import SwiftLinkPreview

class UrlPreviewerModel {
    func getPreview(of url: String, instance: String, handler: @escaping (UrlSummalyEntity) -> Void) {
        if let cache = Cache.shared.getUrlPreview(on: url) {
            DispatchQueue.main.async { handler(cache) }
            return
        }
        
        getPreviewWithSummalyProxy(of: url, instance: instance, handler: { summaly in
            if let summaly = summaly { // プロキシに存在してたら
                handler(summaly)
                return
            }
            
            self.getPreviewWithSLP(of: url, instance: instance, handler: { summalyWithSLP in // 存在してない場合はSLPから取得
                handler(summalyWithSLP)
            })
            
        })
    }
    
    // cf. https://github.com/Kinoshita0623/MisskeyAndroidClient/blob/master/app/src/main/java/jp/panta/misskeyandroidclient/model/api/GetUrlPreview.kt#L32
    private func getPreviewWithSummalyProxy(of url: String, instance: String, handler: @escaping (UrlSummalyEntity?) -> Void) {
        let proxyUrl = "https://\(instance)/url?url=\(url)"
        
        Requestor.get(url: proxyUrl, completion: { _, dataString in
            guard let dataString = dataString else { handler(nil); return }
            let entity = self.decodeJSON(raw: dataString, type: UrlSummalyEntity.self)
            handler(entity)
        })
    }
    
    private func getPreviewWithSLP(of url: String, instance: String, handler: @escaping (UrlSummalyEntity) -> Void) {
        let slp = SwiftLinkPreview(session: URLSession.shared,
                                   workQueue: DispatchQueue.global(),
                                   responseQueue: DispatchQueue.main)
        
        slp.preview(url, onSuccess: { res in
            // UrlSummalyEntityに詰め替える
            let entity = UrlSummalyEntity(title: res.title,
                                          icon: res.icon,
                                          description: res.description,
                                          thumbnail: self.searchImageUrlWithSLP(res),
                                          sitename: res.title,
                                          sensitive: false,
                                          url: url)
            
            Cache.shared.saveUrlPreview(entity, on: url)
            handler(entity)
        }, onError: handleError)
    }
    
    private func searchImageUrlWithSLP(_ response: Response) -> String? {
        guard let url = response.finalUrl?.absoluteURL.absoluteString else { return response.image }
        if url.contains("github.com") {
            return response.icon
        }
        
        return response.image
    }
    
    private func decodeJSON<T>(raw rawJson: String, type: T.Type) -> T? where T: Decodable {
        guard rawJson.count > 0 else { return nil }
        
        do {
            return try JSONDecoder().decode(type, from: rawJson.data(using: .utf8)!)
        } catch {
            print(error)
            return nil
        }
    }
    
    private func handleError(_ error: PreviewError) {}
}
