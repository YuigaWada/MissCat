//
//  NotificationModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/24.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit

public class NotificationsModel {
    private let needMyNoteType = ["mention", "reply", "renote", "quote", "reaction"]
    
    public func loadNotification(untilId: String? = nil, completion: @escaping ([NotificationModel]?) -> Void) {
        MisskeyKit.notifications.get(limit: 20, untilId: untilId ?? "", following: false) { results, error in
            guard let results = results, results.count > 0, error == nil else { completion(nil); return }
            
            if let notificationId = results[0].id {
                Cache.UserDefaults.shared.setLatestNotificationId(notificationId) // 最新の通知をsave
            }
            
            completion(results)
        }
    }
    
    public func getModel(notification: NotificationModel) -> NotificationCell.Model? {
        guard let id = notification.id, let type = notification.type, let user = notification.user else { return nil }
        
        if type == .follow {
            return NotificationCell.Model(notificationId: id,
                                          type: type,
                                          myNote: nil,
                                          replyNote: nil,
                                          fromUser: user,
                                          reaction: nil,
                                          ago: notification.createdAt ?? "")
        }
        
        return getNoteModel(notification: notification, id: id, type: type, user: user)
    }
    
    // 任意のresponseからNotificationCell.Modelを生成する
    public func getModel(type: String?, target: Any?) -> NotificationCell.Model? {
        guard let type = type, let target = target else { return nil }
        // StreamingModel
        switch type {
        case "reply":
            return convertNoteModel(target)
            
        case "notification": // 多分reactionの通知と一対一に対応してるはず
            return convertNotification(target)
            
        default:
            return convertNotification(target)
        }
    }
    
    private func getNoteModel(notification: NotificationModel, id: String, type: ActionType, user: UserModel) -> NotificationCell.Model? {
        guard let note = notification.note else { return nil }
        let isReply = type == .mention || type == .reply
        let isRenote = type == .renote
        let isCommentRenote = type == .quote
        
        // replyかどうかで.noteと.replyの役割が入れ替わる
        var replyNote = isReply ? (note.getNoteCellModel() ?? nil) : nil
        
        var myNote: NoteCell.Model?
        if isReply {
            guard let reply = note.reply else { return nil }
            myNote = reply.getNoteCellModel()
        } else if isRenote {
            guard let renote = note.renote else { return nil }
            myNote = renote.getNoteCellModel()
        } else if isCommentRenote {
            guard let renote = note.renote else { return nil }
            let commentRNTarget = renote.getNoteCellModel()
            commentRNTarget?.onOtherNote = true
            
            replyNote = note.getNoteCellModel()
            replyNote?.commentRNTarget = commentRNTarget
        } else {
            myNote = note.getNoteCellModel()
        }
        
        let cellModel = NotificationCell.Model(notificationId: id,
                                               type: type,
                                               myNote: myNote,
                                               replyNote: replyNote,
                                               fromUser: user,
                                               reaction: notification.reaction,
                                               ago: notification.createdAt ?? "")
        
        return cellModel
    }
    
    // 生のNoteModelをNotificationCell.Modelに変換する
    private func convertNoteModel(_ target: Any) -> NotificationCell.Model? {
        guard let note = target as? NoteModel, let myNote = note.reply, let fromUser = note.user else { return nil }
        
        return NotificationCell.Model(notificationId: note.id ?? "",
                                      type: .reply,
                                      myNote: myNote.getNoteCellModel(),
                                      replyNote: note.getNoteCellModel(),
                                      fromUser: fromUser,
                                      reaction: nil,
                                      ago: note.createdAt ?? "")
    }
    
    private func convertNotification(_ target: Any) -> NotificationCell.Model? {
        guard let target = target as? StreamingModel, let fromUser = target.user else { return nil }
        
        var type: ActionType
        if target.reaction != nil {
            type = .reaction
        } else if target.type == "follow" {
            type = .follow
        } else if target.type == "renote" {
            type = .renote
        } else {
            return nil
        }
        
        return NotificationCell.Model(notificationId: target.id ?? "",
                                      type: type,
                                      myNote: target.note?.getNoteCellModel(),
                                      replyNote: nil,
                                      fromUser: fromUser,
                                      reaction: target.reaction,
                                      ago: target.createdAt ?? "")
    }
}
