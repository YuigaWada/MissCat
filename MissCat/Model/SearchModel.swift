//
//  SearchModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/11.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxSwift

class SearchModel {
    func searchUser(with query: String, sinceId: String = "", untilId: String = "") -> Observable<[UserModel]> {
        return Observable.create { observer in
            let dispose = Disposables.create()
            
            MisskeyKit.search.user(query: query, limit: 40, sinceId: sinceId, untilId: untilId, detail: true) { users, error in
                guard let users = users else { return }
                if let error = error { observer.onError(error); return }
                
                observer.onNext(users)
                observer.onCompleted()
            }
            return dispose
        }
    }
}
