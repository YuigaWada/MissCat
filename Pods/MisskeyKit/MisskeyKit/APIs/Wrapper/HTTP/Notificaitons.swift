//
//  Notificaitons.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/05.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation

extension MisskeyKit {
    public class Notifications {
        
        public func get(limit: Int = 10, sinceId: String = "", untilId: String = "", following: Bool = true, markAsRead: Bool = true, includeTypes: [ActionType] = [], excludeTypes: [ActionType] = [], result callback: @escaping NotificationsCallBack) {
            
            var params = ["limit":limit,
                          "sinceId":sinceId,
                          "untilId":untilId,
                          "following":following,
                          "includeTypes":includeTypes,
                          "excludeTypes":excludeTypes,
                          "markAsRead":markAsRead] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "i/notifications", params: params, type: [NotificationModel].self) { users, error in
                
                if let error = error  { callback(nil, error); return }
                guard let users = users else { callback(nil, error); return }
                
                callback(users,nil)
            }
        }
        
        public func markAllAsRead(result callback: @escaping BooleanCallBack) {
            var params = [:] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notifications/mark-all-as-read", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
    }
}

