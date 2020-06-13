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
    
    func removeUser(user: SecureUser) {
        Cache.UserDefaults.shared.removeUser(userId: user.userId)
    }
    
    /// 削除しようとしているアカウントが紐付けられたタブを削除しておく
    /// - Parameter user: SecureUser
    func checkTabs(for user: SecureUser) {
        Theme.shared.removeUserTabs(for: user)
    }
}
