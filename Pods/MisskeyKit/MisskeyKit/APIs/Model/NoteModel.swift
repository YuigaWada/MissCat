 //
 //  +Notes.swift
 //  MisskeyKit
 //
 //  Created by Yuiga Wada on 2019/11/04.
 //  Copyright © 2019 Yuiga Wada. All rights reserved.
 //

 import Foundation

 public class NoteModel: Codable {
    public var id, createdAt, userId: String?
    public var user: UserModel?
    public var text, cw: String?
    public var visibility: Visibility?
    public var viaMobile: Bool?
    public var isHidden: Bool?
    public var renoteCount, repliesCount: Int?
    public var reactions: [ReactionCount?]?
    public var emojis: [EmojiModel?]?
    public var files: [File?]?
    public var replyId, renoteId: String?
    public var renote: NoteModel?
    public var mentions: [String?]?
    public var visibleUserIds:[String?]?
    public var reply: NoteModel?
    public var tags: [String]?
    public var myReaction: String?
    public var fileIds: [String?]?
    public var app: App?
    public var poll: Poll?
    public var geo: Geo?
    public var _featuredId_: String?
 }
 
 public class App: Codable {
     public var id, name, callbackUrl: String?
     public var permission: [String]?
 }

 // MARK: - File
 public struct File: Codable {
     public var id, createdAt, name, type: String?
     public var md5: String?
     public var size: Int?
     public var isSensitive: Bool?
     public var properties: Properties?
     public var url, thumbnailUrl: String?
     public var folderId, folder, user: String?
 }

 // MARK: - Properties
 public struct Properties: Codable {
     public var width, height: Int?
     public var avgColor: String?
 }

 // MARK: - Reaction
 public struct ReactionCount: Codable {
    public var name: String?
    public var count: String?
    
    public init(name: String, count: String) {
        self.name = name
        self.count = count
    }
 }

 // MARK: - Visibility
 public enum Visibility: String, Codable {
     case `public` = "public"
     case home = "home"
     case followers = "followers"
     case specified = "specified"
 }

 // MARK: - Geo
 public struct Geo: Codable {
     public var coordinates: [String?]?
     public var altitude, accuracy, altitudeAccuracy, heading: Int?
     public var speed: Int?
     
     public init(){
         self.coordinates = []
         self.altitude = 0
         self.accuracy = 0
         self.altitudeAccuracy = 0
         self.heading = 0
         self.speed = 0
     }
 }

 public struct ReactionModel: Codable {
     public var id, createdAt, type: String?
     public var user: UserModel?
 }
 
 
 // MARK: - Poll
 public struct Poll: Codable {
     public var choices: [Choice?]?
     public var multiple: Bool?
     public var expiresAt, expiredAfter: String?
     
     public init() {
         self.multiple = nil
         self.choices = nil
         self.expiredAfter = nil
         self.expiresAt = nil
     }
 }

 
 public struct Choice: Codable {
     public var text: String?
     public var votes: Int?
     public var isVoted: Bool?
 }

 public struct NoteState: Codable {
     public var isFavorited, isWatching: Bool?
 }

 
 extension Geo {
    func toDictionary()-> Dictionary<String, Any> {
        return [
            "coordinates": coordinates as Any,
            "altitude":altitude as Any,
            "accuracy":accuracy as Any,
            "altitudeAccuracy":altitudeAccuracy as Any,
            "heading":heading as Any,
            "speed":heading as Any
        ]
    }
 }
 
 extension Poll {
    func toDictionary()-> Dictionary<String, Any> {
        return [
            "multiple": multiple as Any,
            "choices":choices as Any,
            "expiresAt":expiresAt as Any,
            "expiredAfter":expiredAfter as Any
        ]
    }
 }
