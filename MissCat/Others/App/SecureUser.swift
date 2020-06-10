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
    var apiKey: String?
    
    init(userId: String, instance: String, apiKey: String?) {
        self.userId = userId
        self.instance = instance
        self.apiKey = apiKey
    }
}

extension SecureUser {}
