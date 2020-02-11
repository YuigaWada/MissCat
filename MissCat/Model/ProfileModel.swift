//
//  ProfileModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/12/07.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Down
import MisskeyKit
import UIKit

class ProfileModel {
    public func getUser(userId: String, completion: @escaping (UserModel?) -> Void) {
        MisskeyKit.users.showUser(userId: userId) { user, error in
            guard error == nil else { completion(nil); return }
            completion(user)
        }
    }
}
