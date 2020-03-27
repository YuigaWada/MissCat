//
//  NoteCell.Model.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/22.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxCocoa
import RxDataSources
import RxSwift
import UIKit

// MARK: NoteCell.Model

extension NoteCell {
    public class Model: IdentifiableType, Equatable {
        var isSkelton = false
        var isReactionGenCell = false
        var isRenoteeCell = false
        var renotee: String?
        var baseNoteId: String? // どのcellに対するReactionGenCellなのか
        var isReply: Bool = false // リプライであるかどうか
        var isReplyTarget: Bool = false // リプライ先の投稿であるかどうか
        var fileVisible: Bool = true // ファイルを表示するか
        
        public let identity: String = String(Float.random(in: 1 ..< 100))
        let noteId: String?
        
        public typealias Identity = String
        
        let iconImageUrl: String?
        var iconImage: UIImage?
        
        let userId: String
        
        let displayName: String
        var shapedDisplayName: MFMString?
        
        let username: String
        
        let note: String
        var shapedNote: MFMString?
        
        let ago: String
        let replyCount: Int
        let renoteCount: Int
        var reactions: [ReactionCount]
        var shapedReactions: [NoteCell.Reaction]
        var myReaction: String?
        var files: [File]
        let emojis: [EmojiModel]?
        
        var commentRNTarget: NoteCell.Model?
        var original: NoteModel?
        
        var onOtherNote: Bool = false // 引用RNはNoteCellの上にNoteCellが乗るという二重構造になっているので、内部のNoteCellかどうかを判別する
        var poll: Poll?
        
        init(isSkelton: Bool = false, isReactionGenCell: Bool = false, isRenoteeCell: Bool = false, renotee: String? = nil, baseNoteId: String? = nil, isReply: Bool = false, isReplyTarget: Bool = false, noteId: String? = nil, iconImageUrl: String? = nil, iconImage: UIImage? = nil, userId: String, displayName: String, username: String, note: String, ago: String, replyCount: Int, renoteCount: Int, reactions: [ReactionCount], shapedReactions: [NoteCell.Reaction], myReaction: String? = nil, files: [File], emojis: [EmojiModel]? = nil, commentRNTarget: NoteCell.Model? = nil, original: NoteModel? = nil, onOtherNote: Bool = false, poll: Poll? = nil) {
            self.isSkelton = isSkelton
            self.isReactionGenCell = isReactionGenCell
            self.isRenoteeCell = isRenoteeCell
            self.renotee = renotee
            self.baseNoteId = baseNoteId
            self.isReply = isReply
            self.isReplyTarget = isReplyTarget
            self.noteId = noteId
            self.iconImageUrl = iconImageUrl
            self.iconImage = iconImage
            self.userId = userId
            self.displayName = displayName
            self.username = username
            self.note = note
            self.ago = ago
            self.replyCount = replyCount
            self.renoteCount = renoteCount
            self.reactions = reactions
            self.shapedReactions = shapedReactions
            self.myReaction = myReaction
            self.files = files
            self.emojis = emojis
            self.commentRNTarget = commentRNTarget
            self.original = original
            self.onOtherNote = onOtherNote
            self.poll = poll
        }
        
        public static func == (lhs: NoteCell.Model, rhs: NoteCell.Model) -> Bool {
            return lhs.identity == rhs.identity
        }
        
        // MARK: Statics
        
        static func fakeRenoteecell(renotee: String, renoteeUserName: String, baseNoteId: String) -> NoteCell.Model {
            var renotee = renotee
            if renotee.count > 7 {
                renotee = String(renotee.prefix(10)) + "..."
            }
            
            return NoteCell.Model(isRenoteeCell: true,
                                  renotee: renotee,
                                  baseNoteId: baseNoteId,
                                  noteId: "",
                                  iconImageUrl: "",
                                  iconImage: nil,
                                  userId: "",
                                  displayName: "",
                                  username: renoteeUserName,
                                  note: "",
                                  ago: "",
                                  replyCount: 0,
                                  renoteCount: 0,
                                  reactions: [],
                                  shapedReactions: [],
                                  myReaction: nil,
                                  files: [],
                                  emojis: [],
                                  commentRNTarget: nil,
                                  poll: nil)
        }
        
        static func fakeSkeltonCell() -> NoteCell.Model {
            return NoteCell.Model(isSkelton: true,
                                  isRenoteeCell: false,
                                  renotee: "",
                                  baseNoteId: "",
                                  noteId: "",
                                  iconImageUrl: "",
                                  iconImage: nil,
                                  userId: "",
                                  displayName: "",
                                  username: "",
                                  note: "",
                                  ago: "",
                                  replyCount: 0,
                                  renoteCount: 0,
                                  reactions: [],
                                  shapedReactions: [],
                                  myReaction: nil,
                                  files: [],
                                  emojis: [],
                                  commentRNTarget: nil,
                                  poll: nil)
        }
    }
    
    struct Section {
        var items: [Model]
    }
    
    struct Reaction: IdentifiableType, Equatable {
        typealias Identity = String
        var identity: String
        var noteId: String
        
        var url: String?
        
        var rawEmoji: String?
        var emoji: String?
        
        var isMyReaction: Bool
        
        var count: String
        
        struct Section {
            var items: [Reaction]
        }
    }
}

extension NoteCell.Section: AnimatableSectionModelType {
    typealias Item = NoteCell.Model
    typealias Identity = String
    
    public var identity: String {
        return ""
    }
    
    init(original: NoteCell.Section, items: [NoteCell.Model]) {
        self = original
        self.items = items
    }
}

extension NoteCell.Reaction.Section: AnimatableSectionModelType {
    typealias Item = NoteCell.Reaction
    typealias Identity = String
    
    public var identity: String {
        return ""
    }
    
    init(original: Item.Section, items: [Item]) {
        self = original
        self.items = items
    }
}

extension NoteCell.Model {
    /// ReactionCountをNoteCell.Reactionに変換する
    func getReactions() -> [NoteCell.Reaction] {
        return reactions.map { reaction in
            guard let count = reaction.count, count != "0" else { return nil }
            
            let rawEmoji = reaction.name ?? ""
            let isMyReaction = rawEmoji == self.myReaction
            
            guard rawEmoji != "", let convertedEmojiData = EmojiHandler.handler.convertEmoji(raw: rawEmoji) else {
                // If being not converted
                let reactionModel = NoteCell.Reaction(identity: UUID().uuidString,
                                                      noteId: self.noteId ?? "",
                                                      url: nil,
                                                      rawEmoji: rawEmoji,
                                                      isMyReaction: isMyReaction,
                                                      count: count)
                return reactionModel
            }
            
            var reactionModel: NoteCell.Reaction
            switch convertedEmojiData.type {
            case "default":
                reactionModel = NoteCell.Reaction(identity: UUID().uuidString,
                                                  noteId: self.noteId ?? "",
                                                  url: nil,
                                                  rawEmoji: rawEmoji,
                                                  emoji: convertedEmojiData.emoji,
                                                  isMyReaction: isMyReaction,
                                                  count: count)
            case "custom":
                reactionModel = NoteCell.Reaction(identity: UUID().uuidString,
                                                  noteId: self.noteId ?? "",
                                                  url: convertedEmojiData.emoji,
                                                  rawEmoji: rawEmoji,
                                                  emoji: convertedEmojiData.emoji,
                                                  isMyReaction: isMyReaction,
                                                  count: count)
            default:
                return nil
            }
            
            return reactionModel
        }.compactMap { $0 } // nil除去
    }
}
