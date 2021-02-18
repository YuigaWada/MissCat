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
    struct Profile {
        var bannerUrl: String
        var iconUrl: String
        var name: String
        var username: String
        var description: String
        var isCat: Bool
    }
    
    struct Input {
        let owner: SecureUser?
        let nameYanagi: YanagiText
        let introYanagi: YanagiText
        
        let followButtonTapped: ControlEvent<Void>
        let backButtonTapped: ControlEvent<Void>
        let settingsButtonTapped: ControlEvent<Void>
    }
    
    struct Output {
        let bannerImage: PublishRelay<UIImage> = .init()
        let displayName: PublishRelay<NSAttributedString> = .init()
        let iconImage: PublishRelay<UIImage> = .init()
        let intro: PublishRelay<NSAttributedString> = .init()
        let isCat: PublishRelay<Bool> = .init()
        
        let notesCount: PublishRelay<String> = .init()
        let followCount: PublishRelay<String> = .init()
        let followerCount: PublishRelay<String> = .init()
        let relation: PublishRelay<UserRelationship> = .init()
        
        let showUnfollowAlertTrigger: PublishRelay<Void> = .init()
        let showProfileSettingsTrigger: PublishRelay<Profile> = .init()
        let openSettingsTrigger: PublishRelay<Void> = .init()
        let popViewControllerTrigger: PublishRelay<Void> = .init()
        
        var isMe: Bool = false
    }
    
    struct State {
        var isFollowing: Bool?
    }
    
    private var input: Input
    lazy var output: Output = .init()
    lazy var state: State = .init()
    
    private var userId: String?
    private var relation: UserRelationship?
    private var emojis: [EmojiModel?] = []
    private var profile: Profile?
    
    private var disposeBag: DisposeBag
    private lazy var misskey: MisskeyKit? = {
        guard let owner = input.owner else { return nil }
        return MisskeyKit(from: owner)
    }()
    
    private lazy var model = ProfileModel(from: misskey)
    
    init(with input: Input, and disposeBag: DisposeBag) {
        self.input = input
        self.disposeBag = disposeBag
    }
    
    func setUserId(_ userId: String, isMe: Bool) {
        model.getUser(userId: userId, completion: binding)
        
        output.isMe = isMe
        self.userId = userId
    }
    
    func follow() {
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
    
    func unfollow() {
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
    
    /// プロフィール情報を書き換える
    /// MissCat側で編集したプロフィールの差分を適応するときなどに使う
    /// - Parameter diff: 差分
    func overrideInfo(_ diff: ChangedProfile) {
        guard let profile = profile else { return }
        if let icon = diff.icon {
            output.iconImage.accept(icon)
        }
        
        if let banner = diff.banner {
            output.bannerImage.accept(banner)
        }
        
        if let isCat = diff.isCat {
            output.isCat.accept(isCat)
            self.profile?.isCat = isCat
        }
        
        if let description = diff.description {
            input.introYanagi.resetViewString()
            setDesc(description, externalEmojis: emojis, owner: input.owner)
            self.profile?.description = description
        }
        
        if let name = diff.name {
            input.nameYanagi.resetViewString()
            setName(name: name, username: profile.username, externalEmojis: emojis)
            self.profile?.name = name
        }
    }
    
    /// binding
    /// - Parameter user: UserModel
    private func binding(_ user: UserEntity?) {
        guard let user = user else { return }
        
        profile = user.getProfile()
        
        // Notes || FF
        output.notesCount.accept(user.notesCount?.description ?? "0")
        output.followCount.accept(user.followingCount?.description ?? "0")
        output.followerCount.accept(user.followersCount?.description ?? "0")
        
        setRelation(targetUserId: user.userId)
        setIcon(from: user)
        setName(name: user.name, username: user.username, externalEmojis: user.emojis)
        setDesc(user.description, externalEmojis: user.emojis, owner: input.owner)
        setBanner(from: user)
        
        output.isCat.accept(user.isCat ?? false)
        
        // tapped event
        input.followButtonTapped.subscribe(onNext: { _ in
            if !self.output.isMe {
                if self.state.isFollowing ?? true { // try フォロー解除
                    self.output.showUnfollowAlertTrigger.accept(())
                } else {
                    self.follow()
                }
            } else { // 自分のプロフィールの場合
                guard let profile = self.profile else { return }
                self.output.showProfileSettingsTrigger.accept(profile)
            }
        }).disposed(by: disposeBag)
        
        input.backButtonTapped.subscribe(onNext: { _ in
            self.output.popViewControllerTrigger.accept(())
        }).disposed(by: disposeBag)
        
        input.settingsButtonTapped.subscribe(onNext: { _ in
            self.output.openSettingsTrigger.accept(())
        }).disposed(by: disposeBag)
    }
    
    // MARK: Set
    
    private func setIcon(from user: UserEntity) {
        // Icon Image
        let host = user.host ?? ""
        if let username = user.username, let cachediconImage = Cache.shared.getIcon(username: "\(username)@\(host)") {
            output.iconImage.accept(cachediconImage)
        } else if let iconImageUrl = user.avatarUrl {
            _ = iconImageUrl.toUIImage { image in
                guard let image = image else { return }
                self.output.iconImage.accept(image)
            }
        }
    }
    
    private func setDesc(_ description: String?, externalEmojis: [EmojiModel?]?, owner: SecureUser?) {
        if let externalEmojis = externalEmojis { emojis += externalEmojis } // overrideInfoに備えてemoji情報を保持
        
        let textHex = Theme.shared.currentModel?.colorPattern.hex.text
        if let description = description {
            DispatchQueue.main.async {
                let shaped = description.mfmPreTransform().mfmTransform(owner: owner,
                                                                        font: UIFont(name: "Helvetica", size: 11.0) ?? .systemFont(ofSize: 11.0),
                                                                        externalEmojis: externalEmojis,
                                                                        textHex: textHex)
                
                self.output.intro.accept(shaped.attributed ?? .init())
                shaped.mfmEngine.renderCustomEmojis(on: self.input.introYanagi)
                self.input.introYanagi.renderViewStrings()
                self.input.introYanagi.setNeedsLayout()
            }
        } else {
            output.intro.accept("自己紹介はありません".toAttributedString(family: "Helvetica", size: 11.0, textHex: textHex) ?? .init())
        }
    }
    
    private func setBanner(from user: UserEntity) {
        // Banner Image
        if let bannerUrl = user.bannerUrl {
            _ = bannerUrl.toUIImage { image in
                guard let image = image else { return }
                self.output.bannerImage.accept(image)
            }
        }
    }
    
    private func setName(name: String?, username: String?, externalEmojis: [EmojiModel?]?) {
        if let externalEmojis = externalEmojis { emojis += externalEmojis } // overrideInfoに備えてemoji情報を保持
        
        if let username = username {
            DispatchQueue.main.async {
                let shaped = MFMEngine.shapeDisplayName(owner: self.input.owner,
                                                        name: name ?? username,
                                                        username: username,
                                                        emojis: externalEmojis,
                                                        nameFont: UIFont(name: "Helvetica", size: 13.0),
                                                        usernameFont: UIFont(name: "Helvetica", size: 12.0),
                                                        nameHex: "#ffffff",
                                                        usernameColor: .white)
                
                self.output.displayName.accept(shaped.attributed ?? .init())
                shaped.mfmEngine.renderCustomEmojis(on: self.input.nameYanagi)
                self.input.nameYanagi.renderViewStrings()
                self.input.nameYanagi.setNeedsLayout()
            }
        }
    }
    
    private func setRelation(targetUserId: String) {
        misskey?.users.getUserRelationship(userId: targetUserId) { relation, error in
            guard let relation = relation, error == nil else { return }
            self.output.relation.accept(relation)
            self.state.isFollowing = relation.isFollowing
            self.relation = relation
        }
    }
}

private extension UserEntity {
    /// UserEntityをProfileViewModel.Profileに変更
    func getProfile() -> ProfileViewModel.Profile {
        return .init(bannerUrl: bannerUrl ?? "",
                     iconUrl: avatarUrl ?? "",
                     name: name ?? "",
                     username: username ?? "",
                     description: description ?? "",
                     isCat: isCat ?? false)
    }
}
