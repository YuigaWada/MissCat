//
//  DirectMessageModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/16.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxCocoa
import RxSwift

class DirectMessageModel {
    struct LoadOption {
        let userId: String
        let untilId: String?
    }

    private let misskey: MisskeyKit?
    init(from misskey: MisskeyKit?) {
        self.misskey = misskey
    }
    
    
    private func transformModel(with observer: AnyObserver<DirectMessage>, message: MessageModel) {
        let user: DirectMessage.User = .init(senderId: message.userId ?? "",
                                             displayName: message.user?.username ?? "",
                                             iconUrl: message.user?.avatarUrl ?? "")
        
        let transformed: DirectMessage = .init(text: message.text ?? "",
                                               user: user,
                                               messageId: message.id ?? UUID().uuidString,
                                               date: message.createdAt?.date ?? .init())
        
        transformed.changeReadStatus(read: message.isRead ?? false)
        observer.onNext(transformed)
    }
    
    func load(with option: LoadOption) -> Observable<DirectMessage> {
        let dispose = Disposables.create()
        
        return Observable.create { [unowned self] observer in
            
            let handleResult = { (messages: [MessageModel]?, error: MisskeyKitError?) in
                guard let messages = messages, error == nil else {
                    if let error = error { observer.onError(error) }
                    print(error ?? "error is nil")
                    return
                }
                
                DispatchQueue.global().async {
                    messages.forEach { message in
                        self.transformModel(with: observer, message: message)
                    }
                    observer.onCompleted()
                }
            }
            
            self.misskey?.messaging.getMessageWithUser(userId: option.userId,
                                                    limit: 40,
                                                    untilId: option.untilId ?? "",
                                                    markAsRead: true, result: handleResult)
            return dispose
        }
    }
    
    func send(to userId: String, with text: String) -> Observable<DirectMessage> {
        let dispose = Disposables.create()
        
        return Observable.create { observer in
            self.misskey?.messaging.create(userId: userId, text: text) { sent, error in
                guard let sent = sent, error == nil else {
                    if let error = error { observer.onError(error) }
                    print(error ?? "error is nil")
                    return
                }
                self.transformModel(with: observer, message: sent)
                observer.onCompleted()
            }
            return dispose
        }
    }
}
