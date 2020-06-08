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
        model.getAccountInfo { info in
            // icon
            _ = info?.avatarUrl?.toUIImage { image in
                guard let image = image else { return }
                self.output.iconImage.accept(image)
            }
            
            // text
            
            let name = info?.name
            let username = "@\(info?.username ?? "")"
            
            self.output.name.accept(name ?? username)
            self.output.username.accept(username)
            self.output.instance.accept(user.instance)
        }
    }
}
