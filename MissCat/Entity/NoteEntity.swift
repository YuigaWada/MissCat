//
//  NoteEntity.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/06/30.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import UIKit

class NoteEntity {
    // MARK: Id
    
    let noteId: String?
    let userId: String
    
    // MARK: Icon
    
    let iconImageUrl: String?
    var iconImage: UIImage?
    let isCat: Bool
    
    // MARK: Name
    
    let displayName: String
    let username: String
    let hostInstance: String
    
    // MARK: CW
    
    var hasCw: Bool { return cw != nil }
    let cw: String?
    
    // MARK: Note
    
    let note: String
    var original: NoteModel?
    
    // MARK: Reactions
    
    var reactions: [ReactionCount]
    var myReaction: String?
    
    // MARK: Files
    
    var files: [File]
    
    // MARK: Poll
    
    var poll: Poll?
    
    // MARK: Meta
    
    var emojis: [EmojiModel]?
    let ago: String
    let replyCount: Int
    let renoteCount: Int
    
    init(noteId: String? = nil, iconImageUrl: String? = nil, iconImage: UIImage? = nil, isCat: Bool = false, userId: String = "", displayName: String = "", username: String = "", hostInstance: String = "", note: String = "", ago: String = "", replyCount: Int = 0, renoteCount: Int = 0, reactions: [ReactionCount] = [], shapedReactions: [ReactionEntity] = [], myReaction: String? = nil, files: [File] = [], emojis: [EmojiModel]? = nil, commentRNTarget: NoteCell.Model? = nil, original: NoteModel? = nil, onOtherNote: Bool = false, poll: Poll? = nil, cw: String? = nil) {
        self.noteId = noteId
        self.iconImageUrl = iconImageUrl
        self.iconImage = iconImage
        self.isCat = isCat
        self.userId = userId
        self.displayName = displayName
        self.username = username
        self.hostInstance = hostInstance
        self.note = note
        self.ago = ago
        self.replyCount = replyCount
        self.renoteCount = renoteCount
        self.reactions = reactions
        self.myReaction = myReaction
        self.files = files
        self.emojis = emojis
        self.original = original
        self.poll = poll
        self.cw = cw
    }
}

extension NoteEntity {
    static var mock: NoteEntity {
        return NoteEntity(note: "")
    }
}

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
            let convertedEmojiData = handler.convertEmoji(raw: rawEmoji, external: externalEmojis) else {
            // If being not converted
            
            self.noteId = noteId
            url = nil
            self.rawEmoji = rawEmoji
            self.isMyReaction = isMyReaction
            self.count = count
            return
        }
        
        switch convertedEmojiData.type {
        case "default":
            self.noteId = noteId
            url = nil
            self.rawEmoji = rawEmoji
            emoji = convertedEmojiData.emoji
            self.isMyReaction = isMyReaction
            self.count = count
        case "custom":
            self.noteId = noteId
            url = convertedEmojiData.emoji
            self.rawEmoji = rawEmoji
            emoji = convertedEmojiData.emoji
            self.isMyReaction = isMyReaction
            self.count = count
        case "non-colon":
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

extension ReactionEntity {}
