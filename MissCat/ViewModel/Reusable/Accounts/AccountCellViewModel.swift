//
//  AccountCellViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/06/08.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxCocoa
import RxSwift
import UIKit

class AccountCellViewModel: ViewModelType {
    struct Input {
        let user: SecureUser
    }
    
    struct Output {
        let iconImage: PublishRelay<UIImage> = .init()
        
        let name: PublishRelay<String> = .init()
        let username: PublishRelay<String> = .init()
        let instance: PublishRelay<String> = .init()
    }
    
    struct State {}
    
    private let input: Input
    var output: Output = .init()
    
    private let disposeBag: DisposeBag
    private lazy var misskey = MisskeyKit(from: input.user)
    private lazy var model = AccountCellModel(from: misskey)
    
    init(with input: Input, and disposeBag: DisposeBag) {
        self.input = input
        self.disposeBag = disposeBag
    }
    
    func transform() {
        let user = input.user
        
        // username
        let hasUsername = !user.username.isEmpty
        output.username.accept("@\(user.username)")
        
        // キャッシュから
        if let cache = Cache.shared.getUserInfo(user: user) {
            let name = cache.name
            let username = "@\(cache.username)"
            
            output.name.accept(name)
            output.username.accept(username)
            output.instance.accept(user.instance)
            output.iconImage.accept(cache.image)
            return
        }
        
        // APIから
        model.getAccountInfo { info in
            guard let info = info else { return }
            
            // icon
            _ = info.avatarUrl?.toUIImage { image in
                guard let image = image else { return }
                self.output.iconImage.accept(image)
                let userEntity = UserEntity(from: info)
                self.cache(user: user, userModel: userEntity, image: image)
            }
            
            // text
            
            let name = info.name
            let username = "@\(info.username ?? "")"
            
            self.output.name.accept(name ?? username)
            self.output.username.accept(username)
            self.output.instance.accept(user.instance)
            
            // username情報が保存されていない場合は保存しておく
            if !hasUsername {
                let secureUser = SecureUser(userId: user.userId, username: info.username ?? "", instance: user.instance, apiKey: user.apiKey)
                _ = Cache.UserDefaults.shared.saveUser(secureUser)
            }
        }
    }
    
    private func cache(user: SecureUser, userModel info: UserEntity, image: UIImage) {
        let username = info.username ?? ""
        let cache = Cache.UserInfo(user: user,
                                   name: info.name ?? username,
                                   username: username,
                                   host: user.instance,
                                   image: image)
        
        Cache.shared.saveUserInfo(info: cache) // キャッシュしておく
    }
}
