//
//  AccountCellModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/06/08.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import UIKit

class AccountCellModel {
    private let misskey: MisskeyKit?
    init(from misskey: MisskeyKit?) {
        self.misskey = misskey
    }
    
    func getAccountInfo(completion: @escaping (UserModel?) -> Void) {
        misskey?.users.i { me, _ in
            completion(me)
        }
    }
}
