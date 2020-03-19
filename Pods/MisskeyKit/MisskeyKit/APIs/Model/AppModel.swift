//
//  AppModel.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2020/03/08.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Foundation

public struct AppModel: Codable{
    public let id, name, callbackUrl, secret: String?
    public let permission: [String]?
}
