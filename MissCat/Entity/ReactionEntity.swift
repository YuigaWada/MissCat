//
//  ReactionEntity.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/07/01.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit

class ReactionEntity {
    var noteId: String
    
    var url: String?
    
    var rawEmoji: String?
    var emoji: String?
    
    var isMyReaction: Bool
    
    var count: String
    
    init?(from reaction: ReactionCount, with externalEmojis: [EmojiModel?]?, myReaction: String?, noteId: String, owner: SecureUser) {
        guard let count = reaction.count, count != "0" else { return nil }
        
        let rawEmoji = reaction.name ?? ""
        let isMyReaction = rawEmoji == myReaction
        
        guard rawEmoji != "",
              let handler = EmojiHandler.getHandler(owner: owner),
              let convertedEmojiData = handler.convertEmoji(raw: rawEmoji, external: externalEmojis)
        else {
            // If being not converted
            
            self.noteId = noteId
            url = nil
            self.rawEmoji = rawEmoji
            self.isMyReaction = isMyReaction
            self.count = count
            return
        }
        
        switch convertedEmojiData.type {
        case .default:
            self.noteId = noteId
            url = nil
            self.rawEmoji = rawEmoji
            emoji = convertedEmojiData.emoji
            self.isMyReaction = isMyReaction
            self.count = count
        case .custom:
            self.noteId = noteId
            url = convertedEmojiData.emoji
            self.rawEmoji = rawEmoji
            emoji = convertedEmojiData.emoji
            self.isMyReaction = isMyReaction
            self.count = count
        case .nonColon:
            self.noteId = noteId
            url = nil
            self.rawEmoji = convertedEmojiData.emoji
            emoji = convertedEmojiData.emoji
            self.isMyReaction = isMyReaction
            self.count = count
        default:
            return nil
        }
    }
}
