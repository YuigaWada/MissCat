//
//  AccountsListModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/06/08.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Foundation

class AccountsListModel {
    func getUsers() -> [SecureUser] {
        return Cache.UserDefaults.shared.getUsers()
    }
}
