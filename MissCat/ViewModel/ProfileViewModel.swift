//
//  ProfileViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/12/07.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxCocoa
import RxSwift
import UIKit

class ProfileViewModel: ViewModelType {
    struct Input {
        let yanagi: YanagiText
    }
    
    struct Output {
        let bannerImage: PublishRelay<UIImage> = .init()
        let displayName: PublishRelay<String> = .init()
        let username: PublishRelay<String> = .init()
        let iconImage: PublishRelay<UIImage> = .init()
        let intro: PublishRelay<NSAttributedString> = .init()
        
        let notesCount: PublishRelay<String> = .init()
        let followCount: PublishRelay<String> = .init()
        let followerCount: PublishRelay<String> = .init()
        let relation: PublishRelay<UserRelationship> = .init()
        
        var isMe: Bool = false
    }
    
    struct State {
        var isFollowing: Bool?
    }
    
    private var input: Input
    public lazy var output: Output = .init()
    public lazy var state: State = .init()
    
    private var userId: String?
    private var relation: UserRelationship?
    private lazy var model = ProfileModel()
    
    public init(with input: Input, and disposeBag: DisposeBag) {
        self.input = input
    }
    
    public func setUserId(_ userId: String, isMe: Bool) {
        model.getUser(userId: userId, completion: handleUserInfo)
        
        output.isMe = isMe
        self.userId = userId
    }
    
    public func follow() {
        guard let userId = userId else { return }
        model.follow(userId: userId) { success in
            guard success else { return }
            if self.relation != nil {
                self.relation?.isFollowing = true
                self.state.isFollowing = true
                self.output.relation.accept(self.relation!)
            }
        }
    }
    
    public func unfollow() {
        guard let userId = userId else { return }
        model.unfollow(userId: userId) { success in
            guard success else { return }
            if self.relation != nil {
                self.relation?.isFollowing = false
                self.state.isFollowing = false
                self.output.relation.accept(self.relation!)
            }
        }
    }
    
    private func handleUserInfo(_ user: UserModel?) {
        guard let user = user else { return }
        
        // Notes || FF
        output.notesCount.accept(user.notesCount?.description ?? "0")
        output.followCount.accept(user.followingCount?.description ?? "0")
        output.followerCount.accept(user.followersCount?.description ?? "0")
        
        setRelation(targetUserId: user.id)
        
        // Icon Image
        if let username = user.username, let cachediconImage = Cache.shared.getIcon(username: username) {
            output.iconImage.accept(cachediconImage)
        } else if let iconImageUrl = user.avatarUrl {
            iconImageUrl.toUIImage { image in
                guard let image = image else { return }
                self.output.iconImage.accept(image)
            }
        }
        
        // Description
        if let description = user.description {
            DispatchQueue.main.async {
                let shaped = description.mfmPreTransform().mfmTransform(font: UIFont(name: "Helvetica", size: 11.0) ?? .systemFont(ofSize: 11.0),
                                                                        externalEmojis: user.emojis)
                
                self.output.intro.accept(shaped.attributed ?? .init())
                shaped.mfmEngine.renderCustomEmojis(on: self.input.yanagi)
            }
        } else {
            output.intro.accept("自己紹介はありません".toAttributedString(family: "Helvetica", size: 11.0) ?? .init())
        }
        
        // Banner Image
        if let bannerUrl = user.bannerUrl {
            bannerUrl.toUIImage { image in
                guard let image = image else { return }
                self.output.bannerImage.accept(image)
            }
        }
        
        // username / displayName
        if let username = user.username {
            output.username.accept("@" + username)
            output.displayName.accept(user.name ?? username)
        }
    }
    
    private func setRelation(targetUserId: String) {
        MisskeyKit.users.getUserRelationship(userId: targetUserId) { relation, error in
            guard let relation = relation, error == nil else { return }
            self.output.relation.accept(relation)
            self.state.isFollowing = relation.isFollowing
            self.relation = relation
        }
    }
}
