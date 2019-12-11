//
//  ProfileViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/12/07.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit
import RxSwift
import MisskeyKit

class ProfileViewModel {
    
    public var bannerImage: PublishSubject<UIImage> = .init()
    
    public var displayName: PublishSubject<String> = .init()
    public var username: PublishSubject<String> = .init()
    
    public var iconImage: PublishSubject<UIImage> = .init()
    public var intro: PublishSubject<NSAttributedString> = .init()
    
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
                self.iconImage.onNext(image)
            }
        }
        
        // Description
        if let description = user.description {
            let shaped = model.shape(description: description)
            
            intro.onNext(shaped.toAttributedString(family: "Helvetica", size: 11.0) ?? .init())
        }
        
        // Banner Image
        if let bannerUrl = user.bannerUrl {
            bannerUrl.toUIImage { image in
                guard let image = image else { return }
                self.bannerImage.onNext(image)
            }
        }
        
        // username / displayName
        if let username = user.username {
            self.username.onNext("@" + username)
            displayName.onNext(user.name ?? username)
        }
        
    }
    
}
