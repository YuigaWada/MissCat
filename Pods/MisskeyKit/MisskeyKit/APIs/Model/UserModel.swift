//
//  User.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/04.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//
import Foundation

// MARK: - Me
public struct Me: Codable {
    public var accessToken: String
    public var user: UserModel?
    
    public init(accessToken: String, user: UserModel? = nil) {
        self.accessToken = accessToken
        self.user = user
    }
    
}

public struct UserModel: Codable {
    public var id: String
    public var name: String?
    public var username: String?
    public var description: String?
    public var host: String?
    public var avatarUrl: String?
    public var avatarColor: String?
    public var isAdmin, isBot, isCat: Bool?
    public var emojis: [EmojiModel?]?
    public var url: String?
    public var createdAt, updatedAt: String?
    public var bannerUrl, bannerColor: String?
    public var isLocked, isModerator, isSilenced, isSuspended: Bool?
    public var userDescription, location, birthday: String?
    public var fields: [String?]?
    public var followersCount, followingCount, notesCount: Int?
    public var pinnedNoteIds: [String?]?
    public var pinnedNotes: [NoteModel?]?
    public var pinnedPageId: String?
    public var pinnedPage: PageModel?
    public var twoFactorEnabled, usePasswordLessLogin, securityKeys: Bool?
    public var twitter: Twitter?
    public var github: GitHub?
    public var discord: Discord?
    public var hasUnreadSpecifiedNotes, hasUnreadMentions: Bool?
    public var avatarId, bannerId: String?
    public var autoWatch, alwaysMarkNsfw, carefulBot, autoAcceptFollowed: Bool?
    public var hasUnreadMessagingMessage, hasUnreadNotification: Bool?
    public var pendingReceivedFollowRequestsCount: Int?
    
    
    public struct Twitter: Codable {
        public var id: String?
        public var screenName: String?
    }
    
    public struct GitHub: Codable {
        public var id: String?
        public var login: String?
    }
    
    public struct Discord: Codable {
        public var id: String?
        public var username: String?
        public var discriminator: String?
    }
}

public struct UserRelationship: Codable {
    public var id: String
    public var isFollowing, hasPendingFollowRequestFromYou, hasPendingFollowRequestToYou, isFollowed, isBlocking, isBlocked, isMuted: Bool?
}

public struct BlockList: Codable {
    public var id: String
    public var createdAt: String?
    public var blockeeId: String?
    public var blockee: UserModel?
}

public struct FollowRequestModel: Codable {
    public var id: String
    public var followee: UserModel?
    public var follower: UserModel?
}

