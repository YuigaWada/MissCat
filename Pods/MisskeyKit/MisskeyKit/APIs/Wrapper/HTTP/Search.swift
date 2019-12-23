//
//  Search.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/05.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation


extension MisskeyKit {
    public class Search {
        
        //MARK:- User
        public func user(query: String = "", offset: Int = 0, limit: Int = 10, localOnly: Bool = true, detail: Bool = true, result callback: @escaping UsersCallBack) {
            
            var params = ["query":query,
                          "offset":offset,
                          "limit":limit,
                          "localOnly":localOnly,
                          "detail":detail] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "users/search", params: params, type: [UserModel].self) { users, error in
                
                if let error = error  { callback(nil, error); return }
                guard let users = users else { callback(nil, error); return }
                
                callback(users,nil)
            }
        }
        
        //MARK:- Notes
        
        public func notes(query: String = "", offset: Int = 0, limit: Int = 10, host: String = "", userId: String = "", result callback: @escaping UsersCallBack) {
            
            var params = ["query":query,
                          "offset":offset,
                          "limit":limit,
                          "host":host,
                          "userId":userId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/search", params: params, type: [UserModel].self) { users, error in
                
                if let error = error  { callback(nil, error); return }
                guard let users = users else { callback(nil, error); return }
                
                callback(users,nil)
            }
        }
        
        public func notesByTag( query: [[String]]=[], tag: String = "", reply: Bool = false, renote: Bool = false, withFiles: Bool = false, poll: Bool = false, limit: Int=10, sinceId:String="", untilId: String="", completion callback: @escaping NotesCallBack) {
            
            var params = ["query": query,
                          "tag": tag,
                          "reply": reply,
                          "renote": renote,
                          "withFiles": withFiles,
                          "poll": poll,
                          "limit": limit,
                          "sinceId": sinceId,
                          "untilId": untilId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/search-by-tag", params: params, type: [NoteModel].self) { posts, error in
                if let error = error  { callback(nil, error); return }
                guard let posts = posts else { callback(nil, error); return }
                
                callback(posts,nil)
            }
        }
        
        
        public func hashtags( limit: Int = 10, query: String, offset: Int = 0, completion callback: @escaping ([String]?,MisskeyKitError?)->()) {
            
            var params = ["query": query,
                          "limit": limit,
                          "offset": offset] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "hashtags/search", params: params, type: [String].self) { posts, error in
                if let error = error  { callback(nil, error); return }
                guard let posts = posts else { callback(nil, error); return }
                
                callback(posts,nil)
            }
        }
        
    }
}
