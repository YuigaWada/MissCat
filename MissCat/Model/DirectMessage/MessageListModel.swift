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
    private func transformModel(with observer: AnyObserver<SenderCell.Model>, history: MessageHistoryModel) {
        let myId = Cache.UserDefaults.shared.getCurrentUser()?.userId ?? ""
        let others = [history.recipient, history.user].compactMap { $0 }.filter { $0.id != myId } // チャット相手
        let other = others.count > 0 ? others[0] : history.recipient
        
        let sender: SenderCell.Model = .init(isSkelton: false,
                                             userId: other?.id,
                                             icon: other?.avatarUrl,
                                             name: other?.name,
                                             username: other?.username,
                                             latestMessage: history.text,
                                             createdAt: history.createdAt)
        
        sender.shapedName = MFMEngine.shapeDisplayName(user: other)
        observer.onNext(sender)
    }
    
    func loadHistory() -> Observable<SenderCell.Model> {
        let dispose = Disposables.create()
        
        return Observable.create { [unowned self] observer in
            
            let handleResult = { (lists: [MessageHistoryModel]?, error: MisskeyKitError?) in
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
}
