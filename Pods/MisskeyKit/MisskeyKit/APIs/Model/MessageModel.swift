//
//  MessageModel.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/10.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation


public struct MessageModel: Codable {
    public let id: String?
    public let createdAt: Date?
    public let text: String?
    public let file: File?
    public let recipientId: String?
    public let recipient: UserModel?
}
