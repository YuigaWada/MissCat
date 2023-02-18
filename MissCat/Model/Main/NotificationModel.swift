//
//  NotificationModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/24.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxCocoa
import RxSwift

class NotificationsModel {
    struct LoadOption {
        var isReload: Bool {
            return lastNotifId != nil
        }
        
        let limit: Int
        
        let untilId: String?
        let lastNotifId: String?
    }
    
    private var misskey: MisskeyKit?
    private var owner: SecureUser?
    init(from misskey: MisskeyKit?, owner: SecureUser?) {
        self.misskey = misskey
        self.owner = owner
    }
    
    func change(misskey: MisskeyKit?, owner: SecureUser?) {
        self.misskey = misskey
        self.owner = owner
    }
    
    private let needMyNoteType = ["mention", "reply", "renote", "quote", "reaction"]
    
    func loadNotification(with option: LoadOption, reversed: Bool = false) -> Observable<NotificationModel> {
        let dispose = Disposables.create()
        
        return Observable.create { observer in
            self.misskey?.notifications.get(limit: option.limit, untilId: option.untilId ?? "", following: false) { results, error in
                guard results != nil, results!.count > 0, error == nil else {
                    guard let error = error else { return }
                    observer.onError(error)
                    return
                }
                
                var notifs = results!
                if let notificationId = notifs[0].id {
                    Cache.UserDefaults.shared.setLatestNotificationId(notificationId) // 最新の通知をsave
                }
                
                if option.isReload {
                    // timelineにすでに表示してある投稿を取得した場合、ロードを終了する
                    var newNotif: [NotificationModel] = []
                    for index in 0 ..< notifs.count {
                        let notification = notifs[index]
                        // 表示済みの投稿に当たったらbreak
                        guard option.lastNotifId != notification.id else { break }
                        newNotif.append(notification)
                    }
                    
                    if reversed { newNotif.reverse() }
                    newNotif.forEach { observer.onNext($0) }
                    
                    observer.onCompleted()
                    return
                } else {
                    if reversed {
                        notifs.reverse()
                    }
                    notifs.forEach { observer.onNext($0) }
                }
                
                observer.onCompleted()
            }
            return dispose
        }
    }
    
    func connectStream(apiKey: String) -> Observable<NotificationCell.Model> {
        let dispose = Disposables.create()
        
        return Observable.create { [unowned self] observer in
            let streaming = self.misskey?.streaming
            _ = streaming?.connect(apiKey: apiKey, channels: [.main], response: { (response: Any?, channel: SentStreamModel.Channel?, type: String?, error: MisskeyKitError?) in
                self.handleStream(observer: observer,
                                  response: response,
                                  channel: channel,
                                  type: type,
                                  error: error)
            })
            return dispose
        }
    }
    
    private func handleStream(observer: AnyObserver<NotificationCell.Model>, response: Any?, channel: SentStreamModel.Channel?, type: String?, error: MisskeyKitError?) {
        if let error = error {
            print(error)
            if error == .CannotConnectStream || error == .NoStreamConnection {
                observer.onError(error)
            }
            return
        }
        
        guard let channel = channel, channel == .main, let cellModel = getModel(type: type, target: response) else { return }
        observer.onNext(cellModel)
    }
    
    func getModel(notification: NotificationModel) -> NotificationCell.Model? {
        guard let id = notification.id,
              let actionType = notification.type,
              let user = notification.user,
              let type = NotificationCell.ModelType(from: actionType) else { return nil }
        
        let userEntity = UserEntity(from: user)
        if type == .follow {
            return NotificationCell.Model(notificationId: id,
                                          type: type,
                                          myNote: nil,
                                          replyNote: nil,
                                          fromUser: userEntity,
                                          reaction: nil,
                                          ago: notification.createdAt ?? "")
        }
        
        return getNoteModel(notification: notification, id: id, type: type, user: userEntity)
    }
    
    // 任意のresponseからNotificationCell.Modelを生成する
    func getModel(type: String?, target: Any?) -> NotificationCell.Model? {
        guard let type = type, let target = target else { return nil }
        // StreamingModel
        switch type {
        case "mention":
            return convertNoteModel(target)
            
        case "notification": // 多分reactionの通知と一対一に対応してるはず
            return convertNotification(target)
            
        default:
            return convertNotification(target)
        }
    }
    
    private func getNoteModel(notification: NotificationModel, id: String, type: NotificationCell.ModelType, user: UserEntity) -> NotificationCell.Model? {
        guard let note = notification.note else { return nil }
        let isReply = type == .reply
        let isMention = type == .mention
        let isRenote = type == .renote
        let isCommentRenote = type == .quote
        
        // reply or mentionかどうかで.noteと.replyの役割が入れ替わる
        var replyNote: NoteCell.Model?
        if isReply || isMention {
            replyNote = note.getNoteCellModel(owner: owner)
        }
        
        var myNote: NoteCell.Model?
        
        if isReply {
            guard let reply = note.reply else { return nil }
            myNote = reply.getNoteCellModel(owner: owner)
        } else if isRenote {
            guard let renote = note.renote else { return nil }
            myNote = renote.getNoteCellModel(owner: owner)
        } else if isCommentRenote {
            guard let renote = note.renote else { return nil }
            let commentRNTarget = renote.getNoteCellModel(owner: owner)
            commentRNTarget?.onOtherNote = true
            
            replyNote = note.getNoteCellModel(owner: owner)
            replyNote?.commentRNTarget = commentRNTarget
        } else {
            myNote = note.getNoteCellModel(owner: owner)
        }
        
        let externalEmojis = getExternalEmojis(notification)
        let cellModel = NotificationCell.Model(notificationId: id,
                                               type: type,
                                               myNote: myNote,
                                               replyNote: replyNote,
                                               fromUser: user,
                                               reaction: notification.reaction,
                                               emojis: externalEmojis,
                                               ago: notification.createdAt ?? "")
        
        return cellModel
    }
    
    // 生のNoteModelをNotificationCell.Modelに変換する
    private func convertNoteModel(_ target: Any) -> NotificationCell.Model? {
        guard let note = target as? NoteModel, let fromUser = note.user else { return nil }
        
        let myNote = note.reply
        return NotificationCell.Model(notificationId: note.id ?? "",
                                      type: .reply,
                                      myNote: myNote?.getNoteCellModel(owner: owner), // メンションの場合myNoteが存在しない
                                      replyNote: note.getNoteCellModel(owner: owner),
                                      fromUser: UserEntity(from: fromUser),
                                      reaction: nil,
                                      ago: note.createdAt ?? "")
    }
    
    private func convertNotification(_ target: Any) -> NotificationCell.Model? {
        guard let target = target as? StreamingModel, let fromUser = target.user else { return nil }
        
        var actionType: ActionType
        var targetNote: NoteModel? = target.note
        if target.reaction != nil {
            actionType = .reaction
        } else if target.type == "follow" {
            actionType = .follow
        } else if target.type == "renote" {
            actionType = .renote
            targetNote = target.note?.renote // renoteの場合は相手の投稿(=target.note)のrenote内に自分の投稿が含まれている
        } else {
            return nil
        }
        
        guard let type = NotificationCell.ModelType(from: actionType) else { return nil }
        
        let externalEmojis = getExternalEmojis(target)
        return NotificationCell.Model(notificationId: target.id ?? "",
                                      type: type,
                                      myNote: targetNote?.getNoteCellModel(owner: owner),
                                      replyNote: nil,
                                      fromUser: UserEntity(from: fromUser),
                                      reaction: target.reaction,
                                      emojis: externalEmojis,
                                      ago: target.createdAt ?? "")
    }
    
    /// 流れてきた他インスタンスの絵文字を取得
    /// - Parameter notifications: NotificationModel
    private func getExternalEmojis(_ notification: NotificationModel) -> [EmojiModel] {
        // 仕様上、他インスタンスの絵文字情報はnoteに含まれるっぽい
        let emojisFromNote = EmojiModel.convert(from: notification.note?.emojis) ?? []
        let emojisFromUser = EmojiModel.convert(from: notification.user?.emojis) ?? []
        return emojisFromNote + emojisFromUser
    }
    
    /// 流れてきた他インスタンスの絵文字を取得
    /// - Parameter notifications: NotificationModel
    private func getExternalEmojis(_ notification: StreamingModel) -> [EmojiModel] {
        let emojisFromNote = EmojiModel.convert(from: notification.note?.emojis) ?? []
        let emojisFromUser = EmojiModel.convert(from: notification.user?.emojis) ?? []
        return emojisFromNote + emojisFromUser
    }
}
