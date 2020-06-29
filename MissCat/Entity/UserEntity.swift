//
//  UserEntity.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/06/30.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit

class UserEntity {
    public var userId: String
    public var name: String?
    public var username: String?
    public var description: String?
    public var host: String?
    public var avatarUrl: String?
    public var isCat: Bool?
    public var emojis: [EmojiModel?]?
    public var bannerUrl: String?
    public var followersCount, followingCount, notesCount: Int?
    
    init(id: String, name: String? = nil, username: String? = nil, description: String? = nil, host: String? = nil, avatarUrl: String? = nil, isCat: Bool? = nil, emojis: [EmojiModel?]? = nil, bannerUrl: String? = nil, followersCount: Int? = nil, followingCount: Int? = nil, notesCount: Int? = nil) {
        userId = id
        self.name = name
        self.username = username
        self.description = description
        self.host = host
        self.avatarUrl = avatarUrl
        self.isCat = isCat
        self.emojis = emojis
        self.bannerUrl = bannerUrl
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.notesCount = notesCount
    }
    
    init(from user: UserModel) {
        userId = user.id
        name = user.name
        username = user.username
        description = user.description
        host = user.host
        avatarUrl = user.avatarUrl
        isCat = user.isCat
        emojis = user.emojis
        bannerUrl = user.bannerUrl
        followersCount = user.followersCount
        followingCount = user.followingCount
        notesCount = user.notesCount
    }
}
