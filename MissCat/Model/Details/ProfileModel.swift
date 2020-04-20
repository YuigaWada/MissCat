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
    func getUser(userId: String, completion: @escaping (UserModel?) -> Void) {
        MisskeyKit.users.showUser(userId: userId) { user, error in
            guard error == nil else { completion(nil); return }
            completion(user)
        }
    }
    
    func follow(userId: String, completion: @escaping (Bool) -> Void) {
        MisskeyKit.users.follow(userId: userId) { _, _ in
            completion(true)
        }
    }
    
    func unfollow(userId: String, completion: @escaping (Bool) -> Void) {
        MisskeyKit.users.unfollow(userId: userId) { _, _ in
            completion(true)
        }
    }
}
