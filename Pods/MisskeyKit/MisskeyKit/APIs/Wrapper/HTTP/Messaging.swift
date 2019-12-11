//
//  Messaging.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/10.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation

extension MisskeyKit {
    public class Messaging {
        
        public func readAllMessaging(result callback: @escaping BooleanCallBack) {
            
            var params = [:] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "i/read-all-messaging-messages", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        public func getHistory(limit: Int = 10, result callback: @escaping MessagesCallBack) {
            
            var params = ["limit":limit] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "messaging/history", params: params, type: [MessageModel].self) { users, error in
                
                if let error = error  { callback(nil, error); return }
                guard let users = users else { callback(nil, error); return }
                
                callback(users,nil)
            }
        }
        
        public func getMessageWithUser(userId: String, limit: Int = 10,sinceId: String = "", untilId: String = "",markAsRead: Bool = true, result callback: @escaping MessagesCallBack) {
            
            var params = ["limit":limit,
                          "userId":userId,
                          "sinceId":sinceId,
                          "untilId":untilId,
                          "markAsRead":markAsRead] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "messaging/messages", params: params, type: [MessageModel].self) { users, error in
                
                if let error = error  { callback(nil, error); return }
                guard let users = users else { callback(nil, error); return }
                
                callback(users,nil)
            }
        }
        
        public func create(userId: String,text: String, fileId: String = "", result callback: @escaping OneMessageCallBack) {
                 
                 var params = ["text":text,
                               "userId":userId,
                               "fileId":fileId]as [String : Any]
                 
                 params = params.removeRedundant()
                 MisskeyKit.handleAPI(needApiKey: true, api: "messaging/messages", params: params, type: MessageModel.self) { users, error in
                     
                     if let error = error  { callback(nil, error); return }
                     guard let users = users else { callback(nil, error); return }
                     
                     callback(users,nil)
                 }
             }
        
        public func delete(messageId: String, result callback: @escaping BooleanCallBack) {
            
            var params = ["messageId":messageId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "messaging/messages/delete", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        public func read(messageId: String, result callback: @escaping BooleanCallBack) {
            
            var params = ["messageId":messageId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "messaging/messages/read", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
    }
}
