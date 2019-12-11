//
//  Mute.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/10.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation

extension MisskeyKit {
    public class Mute {
        
        public func create(userId: String, result callback: @escaping BooleanCallBack) {
            
            var params = ["userId":userId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "mute/create", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        public func delete(userId: String, result callback: @escaping BooleanCallBack) {
            
            var params = ["userId":userId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "mute/delete", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
            
        public func getList(limit: Int = 30, sinceId: String = "", untilId: String = "", result callback: @escaping MutesCallBack) {
            
            var params = ["limit":limit,
                          "sinceId":sinceId,
                          "untilId":untilId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "mute/list", params: params, type: [MuteModel].self) { users, error in
                if let error = error  { callback(nil, error); return }
                guard let users = users else { callback(nil, error); return }
                
                callback(users,nil)
            }
        }
        
    }
}
