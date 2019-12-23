//
//  Auth.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/03.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation

public extension MisskeyKit.Auth {
    struct Token: Codable {
        public var token: String
        public var url: String
        
        public init(token: String, url: String) {
            self.token = token
            self.url = url
        }
    }
}
