//
//  NotificationModel.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/05.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation


public struct NotificationModel: Codable {
    public let id: String?
    public let createdAt: String?
    public let type: ActionType?
    public let userId: String?
    public let user: UserModel?
    public let reaction: String?
    public let note: NoteModel?
}


public enum ActionType: String, Codable {
    case follow = "follow"
    case mention = "mention"
    case reply = "reply"
    case renote = "renote"
    case quote = "quote"
    case reaction = "reaction"
    case pollVote = "pollVote"
    case receiveFollowRequest = "receiveFollowRequest"
    case followRequestAccepted = "followRequestAccepted"
}
