//
//  App.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2020/03/08.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Foundation

extension MisskeyKit {
    public class App {
        
        public func create(name: String, description: String, permission:[String], callbackUrl: String? = nil, result callback: @escaping AppCallBack) {
            
            var params = ["name":name,
                          "description":description,
                          "permission":permission,
                          "callbackUrl":callbackUrl] as [String : Any?]
            
            params = params.removeRedundant() as [String : Any]
            MisskeyKit.handleAPI(needApiKey: false, api: "app/create", params: params as [String : Any], type: AppModel.self) { app, error in
                
                if let error = error  { callback(nil, error); return }
                guard let app = app else { callback(nil, error); return }
                
                callback(app,nil)
            }
        }
    }
}
