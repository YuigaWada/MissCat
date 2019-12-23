//
//  Meta.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/05.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation

extension MisskeyKit {
    public class Meta {
        
        public func get(result callback: @escaping MetaCallBack) {
            
            var params = [:] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "meta", params: params, type: MetaModel.self) { meta, error in
                
                if let error = error  { callback(nil, error); return }
                guard let meta = meta else { callback(nil, error); return }
                
                callback(meta,nil)
            }
        }
    }
}
