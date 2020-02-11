//
//  NotificationsViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/24.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxSwift

public class NotificationsViewModel {
    public let notes: PublishSubject<[NotificationCell.Section]> = .init()
    public var dataSource: NotificationDataSource?
    public var cellCount: Int { return cellsModel.count }
    
    private var hasReactionGenCell: Bool = false
    public var cellsModel: [NotificationCell.Model] = []
    
    private lazy var model = NotificationsModel()
    
    init(disposeBag: DisposeBag) {
        loadNotification {
            // 読み込み完了後、Viewに伝達 & Streamingに接続
            self.update(new: self.cellsModel)
            self.connectStream()
        }
    }
    
    public func loadUntilNotification(completion: (() -> Void)? = nil) {
        let untilId = cellsModel[self.cellsModel.count - 1].notificationId
        
        loadNotification(untilId: untilId) {
            self.update(new: self.cellsModel)
            if let completion = completion { completion() }
        }
    }
    
    public func loadNotification(untilId: String? = nil, completion: (() -> Void)? = nil) {
        model.loadNotification(untilId: untilId) { results in
            guard let results = results else { return }
            
            results.forEach { notification in
                guard let cellModel = self.model.getModel(notification: notification) else { return }
                self.cellsModel.append(cellModel)
            }
            
            if let completion = completion { completion() }
        }
    }
    
    private func connectStream() {
        guard let apiKey = MisskeyKit.auth.getAPIKey() else { return }
        
        let streaming = MisskeyKit.Streaming()
        _ = streaming.connect(apiKey: apiKey, channels: [.main], response: handleStream)
    }
    
    private func handleStream(response: Any?, channel: SentStreamModel.Channel?, type: String?, error: MisskeyKitError?) {
        if let error = error {
            print(error)
            if error == .CannotConnectStream || error == .NoStreamConnection { connectStream() }
            return
        }
        
        guard let channel = channel, channel == .main, let cellModel = self.model.getModel(type: type, target: response) else { return }
        cellsModel.insert(cellModel, at: 0)
        
        update(new: cellsModel)
    }
    
    private func update(new: [NotificationCell.Model]) {
        update(new: [NotificationCell.Section(items: new)])
    }
    
    private func update(new: [NotificationCell.Section]) {
        notes.onNext(new)
    }
}
