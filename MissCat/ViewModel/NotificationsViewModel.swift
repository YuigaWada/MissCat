//
//  NotificationsViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/24.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import RxSwift
import MisskeyKit



public class NotificationsViewModel
{
    public let notes: PublishSubject<[NotificationCell.Section]> = .init()
    public var dataSource: NotificationDataSource?
    public var cellCount: Int { return cellsModel.count }
    
    private var hasReactionGenCell: Bool = false
    public var cellsModel: [NotificationCell.Model] = []
    
    private lazy var model = NotificationsModel()
    
    init(disposeBag: DisposeBag) {
        self.loadNotification{
            //読み込み完了後、Viewに伝達 & Streamingに接続
            self.update(new: self.cellsModel)
            self.connectStream()
        }
        
    }
    
    
    public func loadUntilNotification(completion: (()->())? = nil) {
        let untilId = self.cellsModel[self.cellsModel.count - 1].notificationId
        
        self.loadNotification(untilId: untilId) {
            self.update(new: self.cellsModel)
            if let completion = completion { completion() }
        }
    }
    
    
    public func loadNotification(untilId: String? = nil, completion: (()->())? = nil) {
        self.model.loadNotification(untilId: untilId) { results in
            guard let results = results else { return }
            
            results.forEach{ notification in
                guard let cellModel = self.model.getModel(notification: notification) else { return }
                self.cellsModel.append(cellModel)
            }
            
            if let completion = completion { completion() }
        }
    }
    
    
    private func connectStream() {
        guard let apiKey = MisskeyKit.auth.getAPIKey() else { return }
        
        let streaming = MisskeyKit.Streaming()
        let _ = streaming.connect(apiKey: apiKey, channels: [.main], response: self.handleStream)
    }
    
    private func handleStream(response: Any?, channel: SentStreamModel.Channel?, type: String?, error: MisskeyKitError?) {
        if let error = error {
            print(error)
            if error == .CannotConnectStream || error == .NoStreamConnection { self.connectStream() }
            return
        }
        
        guard let channel = channel, channel == .main, let cellModel = self.model.getModel(type: type, target: response) else { return }
        self.cellsModel.insert(cellModel, at: 0)
        
        self.update(new: self.cellsModel)
    }
    
    
    
    
    private func update(new: [NotificationCell.Model]) {
        self.update(new: [NotificationCell.Section(items: new)])
    }
    
    private func update(new: [NotificationCell.Section]) {
        self.notes.onNext(new)
    }
    
}
