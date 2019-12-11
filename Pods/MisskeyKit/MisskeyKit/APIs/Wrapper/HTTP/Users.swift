//
//  Users.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/05.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation

extension MisskeyKit {
    public class Users {
        
        //MARK:- Get User Detail
        public func showUser(userId: String = "", host: String = "", completion callback: @escaping OneUserCallBack) {
            
            var params = ["userId": userId,
                          "host": host] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "users/show", params: params, type: UserModel.self) { user, error in
                if let error = error  { callback(nil, error); return }
                guard let user = user else { callback(nil, error); return }
                
                callback(user,nil)
            }
        }
        
        public func showUser(username: String = "", host: String = "", completion callback: @escaping OneUserCallBack) {
            
            var params = ["username": username,
                          "host": host] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "users/show", params: params, type: UserModel.self) { user, error in
                if let error = error  { callback(nil, error); return }
                guard let user = user else { callback(nil, error); return }
                
                callback(user,nil)
            }
        }
        
        
        public func showUser(userIds: [String] = [], host: String = "", completion callback: @escaping UsersCallBack) {
            
            var params = ["userIds": userIds,
                          "host": host] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "users/show", params: params, type: [UserModel].self) { users, error in
                if let error = error  { callback(nil, error); return }
                guard let users = users else { callback(nil, error); return }
                
                callback(users,nil)
            }
        }
        
        //MARK:- FOR ME
        
        public func getMyAccount(completion callback: @escaping OneUserCallBack) {
            self.i(completion: callback)
        }
        
        //I believe that "i" means I (me).
        public func i(completion callback: @escaping OneUserCallBack) {
            var params = [:] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "i", params: params, type: UserModel.self) { users, error in
                if let error = error  { callback(nil, error); return }
                guard let users = users else { callback(nil, error); return }
                
                callback(users,nil)
            }
        }
        
        public func getAllFavorites(limit: Int = 10, sinceId: String = "", untilId: String = "", completion callback: @escaping NotesCallBack) {
            
            var params = ["limit": limit,
                          "sinceId": sinceId,
                          "untilId": untilId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "i/favorites", params: params, type: [NoteModel].self) { notes, error in
                if let error = error  { callback(nil, error); return }
                guard let notes = notes else { callback(nil, error); return }
                
                callback(notes,nil)
            }
        }
        
        public func getLikedPages(limit: Int = 10, sinceId: String = "", untilId: String = "", completion callback: @escaping PagesCallBack) {
            
            var params = ["limit": limit,
                          "sinceId": sinceId,
                          "untilId": untilId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "i/page-likes", params: params, type: [PageModel].self) { notes, error in
                if let error = error  { callback(nil, error); return }
                guard let notes = notes else { callback(nil, error); return }
                
                callback(notes,nil)
            }
        }
        
        public func getMyPages(limit: Int = 10, sinceId: String = "", untilId: String = "", completion callback: @escaping PagesCallBack) {
            
            var params = ["limit": limit,
                          "sinceId": sinceId,
                          "untilId": untilId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "i/pages", params: params, type: [PageModel].self) { notes, error in
                if let error = error  { callback(nil, error); return }
                guard let notes = notes else { callback(nil, error); return }
                
                callback(notes,nil)
            }
        }
        
        public func updateMyAccount(name: String = "", description: String = "",  lang: String = "",location: String = "",birthday: String = "",avatarId: String = "",bannerId: String = "",fields: [Any] = [],isLocked: Bool?  = nil ,carefulBot: Bool?  = nil ,autoAcceptFollowed: Bool?  = nil ,isBot: Bool?  = nil ,isCat: Bool?  = nil ,autoWatch: Bool?  = nil ,alwaysMarkNsfw: Bool?  = nil ,pinnedPageId: String? = "", result callback: @escaping OneUserCallBack) {
            
            var params = ["name": name,
                          "description": description,
                          "lang": lang,
                          "location": location,
                          "birthday": birthday,
                          "avatarId": avatarId,
                          "bannerId": bannerId,
                          "fields": fields,
                          "isLocked": isLocked,
                          "carefulBot": carefulBot,
                          "autoAcceptFollowed": autoAcceptFollowed,
                          "isBot": isBot,
                          "isCat": isCat,
                          "autoWatch": autoWatch,
                          "alwaysMarkNsfw": alwaysMarkNsfw,
                          "pinnedPageId": autoWatch] as [String : Any?]
            
            params = params.removeRedundant() as [String : Any]
            MisskeyKit.handleAPI(needApiKey: true, api: "i/update", params: params as [String : Any], type: UserModel.self) { myInfo, error in
                if let error = error  { callback(nil, error); return }
                guard let myInfo = myInfo else { callback(nil, error); return }
                
                callback(myInfo,nil)
            }
        }
        
        
        
        //MARK:- For Pin
        public func pin(noteId: String = "", result callback: @escaping BooleanCallBack) {
            
            var params = ["noteId":noteId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "i/pin", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        public func unpin(noteId: String = "", result callback: @escaping BooleanCallBack) {
             
             var params = ["noteId":noteId] as [String : Any]
             
             params = params.removeRedundant()
             MisskeyKit.handleAPI(needApiKey: true, api: "i/unpin", params: params, type: Bool.self) { _, error in
                 callback(error == nil, error)
             }
         }
        
        
        //MARK:- Follow / Unfollow someone
        public func follow(userId: String = "", result callback: @escaping BooleanCallBack) {
            
            var params = ["userId":userId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "following/create", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        public func unfollow(userId: String = "", result callback: @escaping BooleanCallBack) {
            
            var params = ["userId":userId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "following/delete", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        
        
        
        //MARK:- Get Followee / Follower
        public func getFollowers(userId: String = "", username: String = "", host: String = "", limit: Int=10, sinceId:String="", untilId: String="", completion callback: @escaping UsersCallBack) {
            
            var params = ["userId": userId,
                          "username": username,
                          "host": host,
                          "limit": limit,
                          "sinceId": sinceId,
                          "untilId": untilId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "users/followers", params: params, type: [UserModel].self) { posts, error in
                if let error = error  { callback(nil, error); return }
                guard let posts = posts else { callback(nil, error); return }
                
                callback(posts,nil)
            }
        }
        
        public func getFollowing(userId: String = "", username: String = "", host: String = "", limit: Int=10, sinceId:String="", untilId: String="", completion callback: @escaping UsersCallBack) {
            
            var params = ["userId": userId,
                          "username": username,
                          "host": host,
                          "limit": limit,
                          "sinceId": sinceId,
                          "untilId": untilId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "users/following", params: params, type: [UserModel].self) { posts, error in
                if let error = error  { callback(nil, error); return }
                guard let posts = posts else { callback(nil, error); return }
                
                callback(posts,nil)
            }
        }
        
        public func getFrequentlyRepliedUsers(userId: String = "", limit: Int=10, completion callback: @escaping UsersCallBack) {
            
            var params = ["userId": userId,
                          "limit": limit] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "users/get-frequently-replied-users", params: params, type: [UserModel].self) { posts, error in
                if let error = error  { callback(nil, error); return }
                guard let posts = posts else { callback(nil, error); return }
                
                callback(posts,nil)
            }
        }
        
          //MARK:- User Relationship
        public func getUserRelationship(userId: String, result callback: @escaping OneUserRelationshipCallBack) {
            
            var params = ["userId":userId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "users/relation", params: params, type: UserRelationship.self) { users, error in
                
                if let error = error  { callback(nil, error); return }
                guard let users = users else { callback(nil, error); return }
                
                callback(users,nil)
            }
        }
        
        public func getUserRelationship(userIds: [String], result callback: @escaping UserRelationshipsCallBack) {
            
            var params = ["userId":userIds] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "users/relation", params: params, type: [UserRelationship].self) { users, error in
                
                if let error = error  { callback(nil, error); return }
                guard let users = users else { callback(nil, error); return }
                
                callback(users,nil)
            }
        }
        
        //MARK:- For Blocking
        public func block(userId: String, result callback: @escaping BooleanCallBack) {
            
            var params = ["userId":userId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "blocking/create", params: params, type: Bool.self) { _, error in
                callback(error == nil,nil)
            }
        }
        
        public func unblock(userId: String, result callback: @escaping BooleanCallBack) {
            
            var params = ["userId":userId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "blocking/delete", params: params, type: Bool.self) { _, error in
                callback(error == nil,nil)
            }
        }
        
        public func getBlockingList(limit: Int = 30, sinceId: String = "", untilId: String = "", result callback: @escaping BlockListCallBack) {
            
            var params = ["limit": limit,
                          "sinceId": sinceId,
                          "untilId": untilId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "blocking/list", params: params, type: [BlockList].self) { users, error in
                
                if let error = error  { callback(nil, error); return }
                guard let users = users else { callback(nil, error); return }
                
                callback(users,nil)
            }
        }
        
        
        //MARK:- User Report
        public func reportAsAbuse(userIds: [String], comment: String, result callback: @escaping BooleanCallBack) {
            
            var params = ["userId":userIds,
                          "comment":comment] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "users/report-abuse", params: params, type: Bool.self) { _, error in
                callback(error == nil,nil)
            }
        }
        
        
        
        //MARK:- User Recommendation
        public func getUserRecommendation(limit: Int = 10, offset: Int = 0, result callback: @escaping UsersCallBack) {
            
            var params = ["limit":limit,
                          "offset":offset] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "users/recommendation", params: params, type: [UserModel].self) { users, error in
                
                if let error = error  { callback(nil, error); return }
                guard let users = users else { callback(nil, error); return }
                
                callback(users,nil)
            }
        }
        
        
        //MARK:- Follow Requests
        public func acceptFollowRequest(userId: String, comment: String, result callback: @escaping BooleanCallBack) {
            
            var params = ["userId":userId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "following/requests/accept", params: params, type: Bool.self) { _, error in
                callback(error == nil,nil)
            }
        }
        
        //自分が送ったフォローリクエストをキャンセル
        public func cancelFollowRequest(userId: String, comment: String, result callback: @escaping BooleanCallBack) {
            
            var params = ["userId":userId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "following/requests/cancel", params: params, type: Bool.self) { _, error in
                callback(error == nil,nil)
            }
        }
        
        //自分に届いたフォローリクエストをキャンセル
        public func rejectFollowRequest(userId: String, comment: String, result callback: @escaping BooleanCallBack) {
            
            var params = ["userId":userId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "following/requests/reject", params: params, type: Bool.self) { _, error in
                callback(error == nil,nil)
            }
        }
        
        public func getFollowRequests(result callback: @escaping ([FollowRequestModel]?,MisskeyKitError?)->()) {
            
            var params = [:] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "following/requests/list", params: params, type: [FollowRequestModel].self) { users, error in
                
                if let error = error  { callback(nil, error); return }
                guard let users = users else { callback(nil, error); return }
                
                callback(users,nil)
            }
        }
        
    }
}
