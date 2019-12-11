//
//  Groups.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/05.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation

extension MisskeyKit {
    public class Groups {
        
        //MARK:- Invitation
        public func acceptInvitation(inviteId: String = "", result callback: @escaping BooleanCallBack) {
            
            var params = ["inviteId":inviteId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "users/groups/invitations/accept", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        public func rejectInvitation(inviteId: String = "", result callback: @escaping BooleanCallBack) {
            
            var params = ["inviteId":inviteId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "users/groups/invitations/reject", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        public func invite(groupId: String = "", userId: String = "", result callback: @escaping BooleanCallBack) {
            
            var params = ["groupId":groupId,
                          "userId":userId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "users/groups/invite", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        public func pullUser(groupId: String = "", userId: String = "", result callback: @escaping BooleanCallBack) {
            
            var params = ["groupId":groupId,
                          "userId":userId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "users/groups/pull", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        public func transferUser(groupId: String = "", userId: String = "", result callback: @escaping BooleanCallBack) {
            
            var params = ["groupId":groupId,
                          "userId":userId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "users/groups/transfer", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        
        
    }
}
