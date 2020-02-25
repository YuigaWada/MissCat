//
//  MetaModel.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/05.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation

public struct MetaModel: Codable{
    public let maintainerName, maintainerEmail, version, name: String?
    public let uri: String?
    public let welcomeDescription: String?
    public let langs: [String]?
    public let toSUrl: String?
    public let repositoryUrl, feedbackUrl: String?
    public let secure: Bool?
    public let machine, os, node, psql: String?
    public let redis: String?
    public let cpu: CPU?
    public let announcements: [Announcement]?
    public let disableRegistration, disableLocalTimeline, disableGlobalTimeline, enableEmojiReaction: Bool?
    public let driveCapacityPerLocalUserMB, driveCapacityPerRemoteUserMB: Int?
    public let cacheRemoteFiles, enableRecaptcha: Bool?
    public let recaptchaSiteKey, swPublickey, mascotImageUrl: String?
    public let bannerUrl: String?
    public let errorImageUrl, iconUrl: String?
    public let maxNoteTextLength: Int?
    public let emojis: [EmojiModel]?
    public let enableEmail, enableTwitterIntegration, enableGithubIntegration, enableDiscordIntegration: Bool?
    public let enableServiceWorker: Bool?
    public let features: Features?
}

// MARK: - Announcement
public struct Announcement: Codable{
    public let text: String?
    public let image: String?
    public let title: String?
}

// MARK: - CPU
public struct CPU: Codable{
    public let model: String?
    public let cores: Int?
}

// MARK: - Emoji
public struct EmojiModel: Codable{
    public let id: String?
    public let aliases: [String]?
    public let name: String?
    public let url: String?
    public let uri: String?
    public let category: String?
}

//public enum Category: String, Codable{
//    case logo = "Logo"
//    case os = "OS"
//    case cute = "かわいい"
//    case others = "その他"
//    case application = "アプリケーション"
//    case character = "キャラクター"
//    case service = "サービス"
//    case deco = "デコ文字"
//    case action = "行動"
//    case face = "顔"
//    case foodAndDrink = "食べ物・飲み物"
//}

// MARK: - Features
public struct Features: Codable{
    public let registration, localTimeLine, globalTimeLine, elasticsearch: Bool?
    public let recaptcha, objectStorage, twitter, github: Bool?
    public let discord, serviceWorker: Bool?
}
