//
//  UserListModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/13.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxCocoa
import RxSwift

enum UserListType {
    case follow
    case follower
    case list
    case search
}

class UserListModel {
    struct LoadOption {
        let type: UserListType
        let userId: String?
        let query: String?
        let listId: String?
        let untilId: String?
        let loadLimit: Int = 40
    }
    
    private let misskey: MisskeyKit?
    private let owner: SecureUser?
    init(from misskey: MisskeyKit?, owner: SecureUser?) {
        self.misskey = misskey
        self.owner = owner
    }
    
    private func transformUser(with observer: AnyObserver<UserCell.Model>, user: UserModel, reverse: Bool) {
        let userModel = user.getUserCellModel()
        
        userModel.shapedName = MFMEngine.shapeDisplayName(owner: owner, user: user)
        userModel.shapedDescritpion = MFMEngine.shapeString(owner: owner,
                                                            needReplyMark: false,
                                                            text: user.description?.mfmPreTransform() ?? "自己紹介文はありません",
                                                            emojis: user.emojis)
        
        observer.onNext(userModel)
    }
    
    func loadUsers(with option: LoadOption) -> Observable<UserCell.Model> {
        let dispose = Disposables.create()
        
        return Observable.create { [unowned self] observer in
            
            let handleResult = { (posts: [UserModel]?, error: MisskeyKitError?) in
                guard let posts = posts, error == nil else {
                    if let error = error { observer.onError(error) }
                    print(error ?? "error is nil")
                    return
                }
                
                DispatchQueue.global().async {
                    posts.forEach { user in
                        self.transformUser(with: observer, user: user, reverse: false)
                    }
                    observer.onCompleted()
                }
            }
            
            switch option.type {
            case .search:
                guard let query = option.query else { return dispose }
                self.misskey?.search.user(query: query,
                                          limit: option.loadLimit,
                                          untilId: option.untilId ?? "", // TODO: ここOffsetにすべき
                                          localOnly: false,
                                          result: handleResult)
            default:
                break
            }
            
            return dispose
        }
    }
}
