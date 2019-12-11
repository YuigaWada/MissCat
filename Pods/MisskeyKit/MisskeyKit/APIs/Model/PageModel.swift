//
//  PageModel.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/07.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation


public struct PageModel: Codable {
    public let id, createdAt, updatedAt, userId: String?
    public let user: _User? // isnt normal UserModel class.
    public let content: [Content]?
    public let variables: [String?]?
    public let title, name: String?
    public let summary: String?
    public let hideTitleWhenPinned, alignCenter: Bool?
    public let font: String?
    public let eyeCatchingImageId, eyeCatchingImage: String?
    public let attachedFiles: [File?]?
    public let likedCount: Int?
    public let isLiked: Bool?
    
    public struct Content: Codable {
        public let id: String?
        public let contentVar: String?
        public let text, type, event, action: String?
        public let content: String?
        public let message: String?
        public let primary: Bool?
    }
    
    public struct _User: Codable {
        public let id, name, username: String?
        public let host: String?
        public let avatarURL: String?
        public let avatarColor: String?
        public let isBot, isCat: Bool?
        public let emojis: [EmojiModel?]?
    }

}

