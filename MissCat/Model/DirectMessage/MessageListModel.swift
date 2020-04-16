//
//  MessageListModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/16.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxCocoa
import RxSwift

class MessageListModel {
    private func transformModel(with observer: AnyObserver<SenderCell.Model>, history: MessageModel) {
        let sender: SenderCell.Model = .init(isSkelton: false,
                                             userId: history.recipientId,
                                             icon: history.recipient?.avatarUrl,
                                             name: history.recipient?.name,
                                             username: history.recipient?.username,
                                             latestMessage: history.text,
                                             createdAt: history.createdAt)
        
        sender.shapedName = MFMEngine.shapeDisplayName(user: history.recipient)
        observer.onNext(sender)
    }
    
    func loadHistory() -> Observable<SenderCell.Model> {
        let dispose = Disposables.create()
        
        return Observable.create { [unowned self] observer in
            
            let handleResult = { (lists: [MessageModel]?, error: MisskeyKitError?) in
                guard let lists = lists, error == nil else {
                    if let error = error { observer.onError(error) }
                    print(error ?? "error is nil")
                    return
                }
                
                DispatchQueue.global().async {
                    lists.forEach { history in
                        self.transformModel(with: observer, history: history)
                    }
                    observer.onCompleted()
                }
            }
            
            MisskeyKit.messaging.getHistory(result: handleResult)
            return dispose
        }
    }
    
    func transformModel() {}
}
