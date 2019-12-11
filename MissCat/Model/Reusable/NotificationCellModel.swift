//
//  NotificationCellModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/24.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit

public class NotificationCellModel {
    
    public func shapeNote(identifier: String, note: String, isReply: Bool, externalEmojis: [EmojiModel?]?)-> NSAttributedString? {
        let replyHeader: NSMutableAttributedString = isReply ? .getReplyMark() : .init() //リプライの場合は先頭にreplyマークつける
        let attributedText: NSMutableAttributedString = .init(attributedString: replyHeader)
        let newNote = EmojiHandler.handler.emojiEncoder(note: note, externalEmojis: externalEmojis)
        
        attributedText.append(newNote.toAttributedString(family: "Helvetica", size: 11.0) ?? .init())
        
        return attributedText
    }
    
}
