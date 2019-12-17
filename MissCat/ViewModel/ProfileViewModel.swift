//
//  ProfileViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/12/07.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa
import MisskeyKit

class ProfileViewModel: ViewModelType {
    
    struct Input {
        
    }
    
    struct Output {
        let bannerImage: Driver<UIImage>
        let displayName: Driver<String>
        let username: Driver<String>
        let iconImage: Driver<UIImage>
        let intro: Driver<NSAttributedString>
    }
    
    struct State {
    
    }
    
    public lazy var output: Output = .init(bannerImage: self.bannerImage.asDriver(onErrorJustReturn: UIImage()),
                                           displayName: self.displayName.asDriver(onErrorJustReturn: ""),
                                           username: self.username.asDriver(onErrorJustReturn: ""),
                                           iconImage: self.iconImage.asDriver(onErrorJustReturn: UIImage()),
                                           intro: self.intro.asDriver(onErrorJustReturn: NSAttributedString()))
    
    private var bannerImage: PublishRelay<UIImage> = .init()
    
    private var displayName: PublishRelay<String> = .init()
    private var username: PublishRelay<String> = .init()
    
    private var iconImage: PublishRelay<UIImage> = .init()
    private var intro: PublishRelay<NSAttributedString> = .init()
    
    private lazy var model = ProfileModel()
    
    public func setUserId(_ userId: String) {
        model.getUser(userId: userId, completion: handleUserInfo)
    }
    
    private func handleUserInfo(_ user: UserModel?) {
        guard let user = user else { return }
        
        // Icon Image
        if let iconImageUrl = user.avatarUrl {
            iconImageUrl.toUIImage { image in
                guard let image = image else { return }
                self.iconImage.accept(image)
            }
        }
        
        // Description
        if let description = user.description {
            let shaped = model.shape(description: description)
            
            intro.accept(shaped.toAttributedString(family: "Helvetica", size: 11.0) ?? .init())
        }
        
        // Banner Image
        if let bannerUrl = user.bannerUrl {
            bannerUrl.toUIImage { image in
                guard let image = image else { return }
                self.bannerImage.accept(image)
            }
        }
        
        // username / displayName
        if let username = user.username {
            self.username.accept("@" + username)
            self.displayName.accept(user.name ?? username)
        }
        
    }
    
}
