//
//  NotificationCellModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/24.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit

public class NotificationCellModel {
    public func shapeNote(identifier: String, note: String, cache: Cache.NoteOnYanagi?, isReply: Bool, yanagi: YanagiText, externalEmojis: [EmojiModel?]?) -> NSAttributedString? {
        if let cache = cache {
            // YanagiText内部ではattributedTextがsetされた瞬間attachmentの表示が始まるので先にaddしておく
            cache.attachments.forEach { nsAttachment, yanagiAttachment in
                yanagi.addAttachment(ns: nsAttachment, yanagi: yanagiAttachment)
            }
            
            return cache.treatedNote
        }
        let replyHeader: NSMutableAttributedString = isReply ? .getReplyMark() : .init() // リプライの場合は先頭にreplyマークつける
        let body = note.mfmTransform(yanagi: yanagi, externalEmojis: externalEmojis) ?? .init()
        
        return replyHeader + body
    }
}
