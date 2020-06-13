//
//  SecureUser.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/06/11.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Foundation

class SecureUser: Codable {
    let userId: String
    let instance: String
    let username: String
    var apiKey: String?
    
    init(userId: String, username: String, instance: String, apiKey: String?) {
        self.userId = userId
        self.username = username
        self.instance = instance
        self.apiKey = apiKey
    }
}

extension SecureUser {}
