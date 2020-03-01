//
//  Notes.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/04.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation

extension MisskeyKit {
    public class Notes {
        
        //MARK:- Get Notes / Note Info
        
        public func getAllNotes( local: Bool = false, reply: Bool = false, renote: Bool = false, withFiles: Bool = false, poll: Bool = false, limit: Int=10, sinceId:String="", untilId: String="", completion callback: @escaping NotesCallBack) {
            
            var params = ["local": local,
                          "reply": reply,
                          "renote": renote,
                          "withFiles": withFiles,
                          "poll": poll,
                          "limit": limit,
                          "sinceId": sinceId,
                          "untilId": untilId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes", params: params, type: [NoteModel].self) { posts, error in
                if let error = error  { callback(nil, error); return }
                guard let posts = posts else { callback(nil, error); return }
                
                callback(posts,nil)
            }
        }
        
        public func showNote(noteId: String, result callback: @escaping OneNoteCallBack) {
            
            var params = ["noteId":noteId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/show", params: params, type: NoteModel.self) { posts, error in
                
                if let error = error  { callback(nil, error); return }
                guard let posts = posts else { callback(nil, error); return }
                
                callback(posts,nil)
            }
        }
        
        public func getState(noteId: String, result callback: @escaping (NoteState?,MisskeyKitError?)->()) {
            
            var params = ["noteId":noteId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/state", params: params, type: NoteState.self) { posts, error in
                
                if let error = error  { callback(nil, error); return }
                guard let posts = posts else { callback(nil, error); return }
                
                callback(posts,nil)
            }
        }
        
        
        public func getConversation(noteId: String, limit: Int =  10, offset: Int = 0, result callback: @escaping NotesCallBack) {
            
            var params = ["noteId":noteId,
                          "limit":limit,
                          "offset":offset] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/conversation", params: params, type: [NoteModel].self) { posts, error in
                
                if let error = error  { callback(nil, error); return }
                guard let posts = posts else { callback(nil, error); return }
                
                callback(posts,nil)
            }
        }
        
        public func getChildren(noteId: String, limit: Int =  10, sinceId:String="", untilId: String="", result callback: @escaping NotesCallBack) {
            
            var params = ["noteId":noteId,
                          "limit":limit,
                          "sinceId":sinceId,
                          "sinceId":sinceId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/conversation", params: params, type: [NoteModel].self) { posts, error in
                
                if let error = error  { callback(nil, error); return }
                guard let posts = posts else { callback(nil, error); return }
                
                callback(posts,nil)
            }
        }
        
        
        public func getUserNotes(includeReplies:Bool = true, includeMyRenotes: Bool = true, userId: String = "", fileType: [String] = [], excludeNsfw: Bool = true, withFiles: Bool = false, limit: Int=10, sinceDate:Int=0, untilDate: Int=0, sinceId:String="", untilId: String="", completion callback: @escaping NotesCallBack) {
            
            var params = ["fileType": fileType,
                          "excludeNsfw": excludeNsfw,
                          "withFiles": withFiles,
                          "untilDate": untilDate,
                          "sinceDate": sinceDate,
                          "includeReplies": includeReplies,
                          "includeMyRenotes": includeMyRenotes,
                          "limit": limit,
                          "userId": userId,
                          "sinceId": sinceId,
                          "untilId": untilId] as [String : Any]
            
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "users/notes", params: params, type: [NoteModel].self) { posts, error in
                
                if let error = error  { callback(nil, error); return }
                guard let posts = posts else { callback(nil, error); return }
                
                callback(posts,nil)
            }
        }
        
        public func getMentionsForMe(following:Bool = true, limit: Int=10, sinceId:String="", untilId: String="",visibility: Visibility = .public, completion callback: @escaping NotesCallBack) {
            
            var params = ["following": following,
                          "visibility": visibility,
                          "limit": limit,
                          "sinceId": sinceId,
                          "untilId": untilId] as [String : Any]
            
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/mentions", params: params, type: [NoteModel].self) { posts, error in
                
                if let error = error  { callback(nil, error); return }
                guard let posts = posts else { callback(nil, error); return }
                
                callback(posts,nil)
            }
        }
        
        
        
        //MARK:- Get Timeline
        
        public func getTimeline( includeMyRenotes: Bool = true, includeRenotedMyNotes: Bool = true, withFiles: Bool = false, includeLocalRenotes: Bool = true, limit: Int=10, sinceDate:Int=0, untilDate: Int=0, sinceId:String="", untilId: String="", completion callback: @escaping NotesCallBack) {
            
            var params = ["includeMyRenotes": includeMyRenotes,
                          "includeRenotedMyNotes": includeRenotedMyNotes,
                          "includeLocalRenotes": includeLocalRenotes,
                          "withFiles": withFiles,
                          "untilDate": untilDate,
                          "sinceDate": sinceDate,
                          "limit": limit,
                          "sinceId": sinceId,
                          "untilId": untilId] as [String : Any]
            
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/timeline", params: params, type: [NoteModel].self) { posts, error in
                
                if let error = error  { callback(nil, error); return }
                guard let posts = posts else { callback(nil, error); return }
                
                callback(posts,nil)
            }
        }
        
        public func getGlobalTimeline(withFiles: Bool = false, limit: Int=10, sinceDate:Int=0, untilDate: Int=0, sinceId:String="", untilId: String="", completion callback: @escaping NotesCallBack) {
            
            var params = ["withFiles": withFiles,
                          "untilDate": untilDate,
                          "sinceDate": sinceDate,
                          "limit": limit,
                          "sinceId": sinceId,
                          "untilId": untilId] as [String : Any]
            
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/global-timeline", params: params, type: [NoteModel].self) { posts, error in
                
                if let error = error  { callback(nil, error); return }
                guard let posts = posts else { callback(nil, error); return }
                
                callback(posts,nil)
            }
        }
        
        public func getHybridTimeline( includeMyRenotes: Bool = true, includeRenotedMyNotes: Bool = true, withFiles: Bool = false, includeLocalRenotes: Bool = true, limit: Int=10, sinceDate:Int=0, untilDate: Int=0, sinceId:String="", untilId: String="", completion callback: @escaping NotesCallBack) {
            
            var params = ["includeMyRenotes": includeMyRenotes,
                          "includeRenotedMyNotes": includeRenotedMyNotes,
                          "includeLocalRenotes": includeLocalRenotes,
                          "withFiles": withFiles,
                          "untilDate": untilDate,
                          "sinceDate": sinceDate,
                          "limit": limit,
                          "sinceId": sinceId,
                          "untilId": untilId] as [String : Any]
            
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/hybrid-timeline", params: params, type: [NoteModel].self) { posts, error in
                
                if let error = error  { callback(nil, error); return }
                guard let posts = posts else { callback(nil, error); return }
                
                callback(posts,nil)
            }
        }
        
        public func getLocalTimeline( fileType: [String] = [], excludeNsfw: Bool = true, withFiles: Bool = false, limit: Int=10, sinceDate:Int=0, untilDate: Int=0, sinceId:String="", untilId: String="", completion callback: @escaping NotesCallBack) {
            
            var params = ["fileType": fileType,
                          "excludeNsfw": excludeNsfw,
                          "withFiles": withFiles,
                          "untilDate": untilDate,
                          "sinceDate": sinceDate,
                          "limit": limit,
                          "sinceId": sinceId,
                          "untilId": untilId] as [String : Any]
            
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/local-timeline", params: params, type: [NoteModel].self) { posts, error in
                
                if let error = error  { callback(nil, error); return }
                guard let posts = posts else { callback(nil, error); return }
                
                callback(posts,nil)
            }
        }
        
        public func getUserListTimeline(listId: String = "", includeMyRenotes: Bool = true, includeRenotedMyNotes: Bool = true, withFiles: Bool = false, includeLocalRenotes: Bool = true, limit: Int=10, sinceDate:Int=0, untilDate: Int=0, sinceId:String="", untilId: String="", completion callback: @escaping NotesCallBack) {
            
            var params = ["listId": listId,
                          "includeMyRenotes": includeMyRenotes,
                          "includeRenotedMyNotes": includeRenotedMyNotes,
                          "includeLocalRenotes": includeLocalRenotes,
                          "withFiles": withFiles,
                          "untilDate": untilDate,
                          "sinceDate": sinceDate,
                          "limit": limit,
                          "sinceId": sinceId,
                          "untilId": untilId] as [String : Any]
            
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/user-list-timeline", params: params, type: [NoteModel].self) { posts, error in
                
                if let error = error  { callback(nil, error); return }
                guard let posts = posts else { callback(nil, error); return }
                
                callback(posts,nil)
            }
        }
        
        
        
        //MARK:- Featured
        public func getFeatured(limit: Int=10, result callback: @escaping NotesCallBack) {
            
            var params = ["limit":limit] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/featured", params: params, type: [NoteModel].self) { posts, error in
                
                if let error = error  { callback(nil, error); return }
                guard let posts = posts else { callback(nil, error); return }
                
                callback(posts,nil)
            }
        }
        
        
        //MARK:- Create/Delete Note
        
        public func createNote(visibility:Visibility = Visibility.public, visibleUserIds: [String]=[], text: String, cw:String = "", viaMobile: Bool = true, localOnly: Bool = false, noExtractMentions: Bool = false, noExtractHashtags: Bool = false, noExtractEmojis: Bool = false, geo: Geo? = nil, fileIds: [String] = [ ], replyId: String = "", poll: Poll? = nil,  completion callback: @escaping OneNoteCallBack) {
            
            var params = ["visibility": visibility.rawValue,
                          "visibleUserIds": visibleUserIds,
                          "text": text,
                          "viaMobile": viaMobile,
                          "localOnly": localOnly,
                          "noExtractMentions": noExtractMentions,
                          "noExtractHashtags": noExtractHashtags,
                          "noExtractEmojis": noExtractEmojis,
                          "fileIds": fileIds,
                          "replyId": replyId,
                          "geo": geo != nil ? geo!.toDictionary() : geo as Any,
                          "poll": poll != nil ? poll!.toDictionary() : poll as Any] as [String : Any]
            
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/create", params: params, type: NoteModel.self) { posts, error in
                if let error = error  { callback(nil, error); return }
                guard let posts = posts else { callback(nil, error); return }
                
                callback(posts,nil)
            }
        }
        
        public func deletePost(noteId: String, result callback: @escaping BooleanCallBack) {
            
            var params = ["noteId":noteId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/delete", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        //MARK:- Favorite
        public func createFavorite(noteId: String, result callback: @escaping BooleanCallBack) {
            
            var params = ["noteId":noteId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/favorites/create", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        public func deleteFavorite(noteId: String, result callback: @escaping BooleanCallBack) {
            
            var params = ["noteId":noteId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/favorites/delete", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        //MARK:- Reaction
        
        //ReactionModel
        public func getReactions(noteId: String, limit: Int = 10, sinceId: String="", untilId: String = "", offset: Int = 0, result callback: @escaping ReactionsCallBack) {
            
            var params = ["noteId":noteId,
                          "limit":limit,
                          "sinceId":sinceId,
                          "untilId":untilId,
                          "offset":offset] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/reactions", params: params, type: [ReactionModel].self) { posts, error in
                
                if let error = error  { callback(nil, error); return }
                guard let posts = posts else { callback(nil, error); return }
                
                callback(posts,nil)
            }
        }

        
        public func createReaction(noteId: String, reaction:String, result callback: @escaping BooleanCallBack) {
            
            var params = ["noteId":noteId,"reaction":reaction] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/reactions/create", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        public func deleteReaction(noteId: String, result callback: @escaping BooleanCallBack) {
            
            var params = ["noteId":noteId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/reactions/delete", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        //MARK:- Renote
        public func getRenotes(noteId: String, limit: Int = 10, sinceId: String="", untilId: String = "", result callback: @escaping NotesCallBack) {
            
            var params = ["noteId":noteId,
                          "limit":limit,
                          "sinceId":sinceId,
                          "untilId":untilId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/renotes", params: params, type: [NoteModel].self) { posts, error in
                
                if let error = error  { callback(nil, error); return }
                guard let posts = posts else { callback(nil, error); return }
                
                callback(posts,nil)
            }
        }
        
        
        public func renote(renoteId: String, quote: String = "", visibility:Visibility = Visibility.public, visibleUserIds: [String]=[], cw:String = "", viaMobile: Bool = true, localOnly: Bool = false, noExtractMentions: Bool = true, noExtractHashtags: Bool = true, noExtractEmojis: Bool = true, geo: Geo? = nil, fileIds: [String] = [ ], replyId: String = "", poll: Poll? = nil,  completion callback: @escaping OneNoteCallBack) {
            
            var params = ["renoteId": renoteId,
                          "text": quote,
                          "visibility": visibility.rawValue,
                          "visibleUserIds": visibleUserIds,
                          "viaMobile": viaMobile,
                          "localOnly": localOnly,
                          "noExtractMentions": noExtractMentions,
                          "noExtractHashtags": noExtractHashtags,
                          "noExtractEmojis": noExtractEmojis,
                          "fileIds": fileIds,
                          "replyId": replyId,
                          "geo": geo != nil ? geo!.toDictionary() : geo as Any,
                          "poll": poll != nil ? poll!.toDictionary() : poll as Any] as [String : Any]
            
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/create", params: params, type: NoteModel.self) { posts, error in
                if let error = error  { callback(nil, error); return }
                guard let posts = posts else { callback(nil, error); return }
                
                callback(posts,nil)
            }
        }
        
        
        
        
        public func unrenote(noteId: String, result callback: @escaping BooleanCallBack) {
            
            var params = ["noteId":noteId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/unrenote", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        
        //MARK:- Replies
        public func getReplies(noteId: String, limit: Int = 10, sinceId: String="", untilId: String = "", result callback: @escaping NotesCallBack) {
            
            var params = ["noteId":noteId,
                          "limit":limit,
                          "sinceId":sinceId,
                          "untilId":untilId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/replies", params: params, type: [NoteModel].self) { posts, error in
                
                if let error = error  { callback(nil, error); return }
                guard let posts = posts else { callback(nil, error); return }
                
                callback(posts,nil)
            }
        }
        
        //MARK:- Watching
        public func watchNote(noteId: String, result callback: @escaping BooleanCallBack) {
            
            var params = ["noteId":noteId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/watching/create", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        public func unWatchNote(noteId: String, result callback: @escaping BooleanCallBack) {
            
            var params = ["noteId":noteId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/watching/delete", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        //MARK:- Marking
        
        public func readAllUnreadNotes(result callback: @escaping BooleanCallBack) {
            
            var params = [:] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "i/read-all-unread-notes", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        //MARK:- Voting
        
        public func vote(noteId: String, choice: String, result callback: @escaping BooleanCallBack) {
            
            var params = ["noteId":noteId,
                          "choice":choice] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "notes/polls/vote", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        
        
    }
}
