//
//  NotificationsViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/24.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxSwift

class NotificationsViewModel {
    
    let notes: PublishSubject<[NotificationCell.Section]> = .init()
    var dataSource: NotificationDataSource?
    var cellCount: Int { return cellsModel.count }
    var owner: SecureUser?
    
    private var hasReactionGenCell: Bool = false
    var cellsModel: [NotificationCell.Model] = []
    
    private var disposeBag: DisposeBag
    private lazy var model = NotificationsModel()
    
    init(disposeBag: DisposeBag) {
        self.disposeBag = disposeBag
        self.owner = Cache.UserDefaults.shared.getCurrentUser()
    }
    
    // MARK: Load
    
    func initialLoad() {
        loadNotification {
            // 読み込み完了後、Viewに伝達 & Streamingに接続
            self.connectStream()
        }
    }
    
    func loadUntilNotification(completion: (() -> Void)? = nil) {
        let untilId = cellsModel[cellsModel.count - 1].notificationId
        
        loadNotification(untilId: untilId) {
            completion?()
        }
    }
    
    func loadNotification(untilId: String? = nil, lastNotifId: String? = nil, completion: (() -> Void)? = nil) {
        let option: NotificationsModel.LoadOption = .init(limit: 20, untilId: untilId, lastNotifId: lastNotifId)
        
        var tempCells: [NotificationCell.Model] = []
        model.loadNotification(with: option, reversed: true).subscribe(onNext: { notification in
            guard let cellModel = self.model.getModel(notification: notification) else { return }
            
            self.shapeModel(cellModel)
            self.removeDuplicated(with: cellModel, array: &tempCells)
            tempCells.insert(cellModel, at: 0)
            
        }, onCompleted: {
            if untilId == nil {
                self.cellsModel = tempCells + self.cellsModel
            } else {
                self.cellsModel += tempCells
            }
            
            self.update(new: self.cellsModel)
            completion?()
        }).disposed(by: disposeBag)
    }
    
    // MARK: Streaming
    
    private func connectStream() {
        guard let apiKey = MisskeyKit.auth.getAPIKey() else { return }
        model.connectStream(apiKey: apiKey).subscribe(onNext: { cellModel in
            self.shapeModel(cellModel)
            self.removeDuplicated(with: cellModel, array: &self.cellsModel)
            
            self.cellsModel.insert(cellModel, at: 0)
            self.update(new: self.cellsModel)
        }, onError: { _ in
            self.reloadNotes {
                self.connectStream()
            }
        }).disposed(by: disposeBag)
    }
    
    func reloadNotes(_ completion: (() -> Void)? = nil) {
        guard cellsModel.count > 0 else { return }
        
        let lastNotifId = cellsModel[0].notificationId
        loadNotification(lastNotifId: lastNotifId, completion: completion)
    }
    
    // MARK: Utilities
    
    private func shapeModel(_ cellModel: NotificationCell.Model) {
        if cellModel.type == .mention || cellModel.type == .reply || cellModel.type == .quote,
            let replyNote = cellModel.replyNote {
            MFMEngine.shapeModel(replyNote)
        } else {
            MFMEngine.shapeModel(cellModel)
        }
    }
    
    /// 何らかの理由で重複しておくられてくるモデルを炙り出してremoveする
    private func removeDuplicated(with cellModel: NotificationCell.Model, array: inout [NotificationCell.Model]) {
        // 例えば、何度もリアクションを変更されたりすると重複して送られてくる
        let duplicated = array.filter {
            guard let fromUserId = $0.fromUser?.id, let myNoteId = $0.myNote?.noteId else { return false }
            
            let sameUser = fromUserId == cellModel.fromUser?.id
            let sameMyNote = myNoteId == cellModel.myNote?.noteId
            let sameType = $0.type == cellModel.type
            
            if let replyNote = $0.replyNote, let _replyNote = cellModel.replyNote {
                let sameReplyNote = replyNote.noteId == _replyNote.noteId
                return sameUser && sameMyNote && sameType && sameReplyNote
            }
            
            return sameUser && sameMyNote && sameType
        }
        
        // 新しいバージョンの通知のみ表示する
        duplicated
            .compactMap { array.firstIndex(of: $0) }
            .forEach { array.remove(at: $0) }
    }
    
    private func update(new: [NotificationCell.Model]) {
        update(new: [NotificationCell.Section(items: new)])
    }
    
    private func update(new: [NotificationCell.Section]) {
        notes.onNext(new)
    }
}
