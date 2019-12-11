//
//  ListModel.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/06.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation

public struct ListModel: Codable {
    public let id, createdAt, name: String?
    public let userIds: [String?]?
}
