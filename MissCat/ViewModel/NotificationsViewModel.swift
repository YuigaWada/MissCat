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
    private let usernameFont = UIFont.systemFont(ofSize: 11.0)
    
    init(disposeBag: DisposeBag) {
        loadNotification {
            // 読み込み完了後、Viewに伝達 & Streamingに接続
            self.update(new: self.cellsModel)
            self.connectStream()
        }
    }
    
    public func loadUntilNotification(completion: (() -> Void)? = nil) {
        let untilId = cellsModel[cellsModel.count - 1].notificationId
        
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
                if cellModel.type == .mention || cellModel.type == .reply, let replyNote = cellModel.replyNote {
                    self.shapeModel(replyNote)
                } else {
                    self.shapeModel(cellModel)
                }
                
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
        
        guard let channel = channel, channel == .main, let cellModel = model.getModel(type: type, target: response) else { return }
        shapeModel(cellModel)
        cellsModel.insert(cellModel, at: 0)
        
        update(new: cellsModel)
    }
    
    private func shapeModel(_ cellModel: NotificationCell.Model) {
        guard let myNote = cellModel.myNote else { return }
        cellModel.myNote?.shapedNote = shapeNote(myNote)
        cellModel.myNote?.shapedDisplayName = shapeDisplayName(myNote)
        
        if let commentRNTarget = myNote.commentRNTarget {
            commentRNTarget.shapedNote = shapeNote(commentRNTarget)
            commentRNTarget.shapedDisplayName = shapeDisplayName(commentRNTarget)
        }
    }
    
    private func shapeModel(_ cellModel: NoteCell.Model) {
        cellModel.shapedNote = shapeNote(cellModel)
        cellModel.shapedDisplayName = shapeDisplayName(cellModel)
        
        if let commentRNTarget = cellModel.commentRNTarget {
            commentRNTarget.shapedNote = shapeNote(commentRNTarget)
            commentRNTarget.shapedDisplayName = shapeDisplayName(commentRNTarget)
        }
    }
    
    private func shapeNote(_ cellModel: NoteCell.Model) -> MFMString {
        let replyHeader: NSMutableAttributedString = cellModel.isReply ? .getReplyMark() : .init() // リプライの場合は先頭にreplyマークつける
        let mfmString = cellModel.note.mfmTransform(font: UIFont(name: "Helvetica", size: 11.0) ?? .systemFont(ofSize: 11.0),
                                                    externalEmojis: cellModel.emojis,
                                                    lineHeight: 30)
        
        return MFMString(mfmEngine: mfmString.mfmEngine, attributed: replyHeader + (mfmString.attributed ?? .init()))
    }
    
    private func shapeDisplayName(_ cellModel: NoteCell.Model) -> MFMString {
        let mfmString = cellModel.displayName.mfmTransform(font: UIFont(name: "Helvetica", size: 10.0) ?? .systemFont(ofSize: 10.0),
                                                           externalEmojis: cellModel.emojis,
                                                           lineHeight: 25)
        
        return MFMString(mfmEngine: mfmString.mfmEngine,
                         attributed: (mfmString.attributed ?? .init()) + " @\(cellModel.username)".getAttributedString(font: usernameFont,
                                                                                                                       color: .darkGray))
    }
    
    private func update(new: [NotificationCell.Model]) {
        update(new: [NotificationCell.Section(items: new)])
    }
    
    private func update(new: [NotificationCell.Section]) {
        notes.onNext(new)
    }
}
