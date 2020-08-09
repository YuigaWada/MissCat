//
//  ProfileModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/12/07.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import UIKit

class ProfileModel {
    private let misskey: MisskeyKit?
    init(from misskey: MisskeyKit?) {
        self.misskey = misskey
    }
    
    func getUser(userId: String, completion: @escaping (UserEntity?) -> Void) {
        misskey?.users.showUser(userId: userId) { user, error in
            guard error == nil, let user = user else { completion(nil); return }
            completion(UserEntity(from: user))
        }
    }
    
    func follow(userId: String, completion: @escaping (Bool) -> Void) {
        misskey?.users.follow(userId: userId) { _, _ in
            completion(true)
        }
    }
    
    func unfollow(userId: String, completion: @escaping (Bool) -> Void) {
        misskey?.users.unfollow(userId: userId) { _, _ in
            completion(true)
        }
    }
}
