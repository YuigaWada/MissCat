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
        guard let id = notification.id, let type = notification.type, let user = notification.user, let note = notification.note else { return nil }
        
        let isReply = type == .mention || type == .reply
        let isRenote = type == .renote
        
        // replyかどうかで.noteと.replyの役割が入れ替わる
        let replyNote = isReply ? (note.getNoteCellModel() ?? nil) : nil
        
        var myNote: NoteCell.Model?
        if isReply {
            guard let reply = note.reply else { return nil }
            myNote = reply.getNoteCellModel()
        } else if isRenote {
            guard let renote = note.renote else { return nil }
            myNote = renote.getNoteCellModel()
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
    
    // 任意のresponseからNotificationCell.Modelを生成する
    public func getModel(type: String?, target: Any?) -> NotificationCell.Model? {
        guard let type = type, let target = target else { return nil }
        // StreamingModel
        switch type {
        case "mention":
            return convertNoteModel(target)
            
        case "notification": // 多分reactionの通知と一対一に対応してるはず
            return convertNotification(target)
            
        default:
            return nil
        }
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
        guard let target = target as? StreamingModel, let reaction = target.reaction, let toNote = target.note, let fromUser = target.user else { return nil }
        
        return NotificationCell.Model(notificationId: target.id ?? "",
                                      type: .reaction,
                                      myNote: toNote.getNoteCellModel(),
                                      replyNote: nil,
                                      fromUser: fromUser,
                                      reaction: reaction,
                                      ago: target.createdAt ?? "")
    }
}
