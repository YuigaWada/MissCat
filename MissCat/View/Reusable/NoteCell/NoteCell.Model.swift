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
    class Model: CellModel {
        // MARK: Main
        
        var type: ModelType
        var owner: SecureUser?
        var noteEntity: NoteEntity
        
        // MARK: Flag
        
        var renotee: String?
        var baseNoteId: String? // どのcellに対するReactionGenCellなのか
        var isReply: Bool = false // リプライであるかどうか
        var isReplyTarget: Bool = false // リプライ先の投稿であるかどうか
        var fileVisible: Bool = true // ファイルを表示するか
        var onOtherNote: Bool = false // 引用RNはNoteCellの上にNoteCellが乗るという二重構造になっているので、内部のNoteCellかどうかを判別する
        
        // MARK: Name
        
        var shapedDisplayName: MFMString?
        
        // MARK: CW
        
        var shapedCw: MFMString?
        
        // MARK: Note
        
        var shapedNote: MFMString?
        var shapedReactions: [NoteCell.Reaction] = []
        var commentRNTarget: NoteCell.Model?
        
        init(type: NoteCell.ModelType = .model, owner: SecureUser?, entity: NoteEntity = .mock, commentRNTarget: NoteCell.Model? = nil, renotee: String? = nil, baseNoteId: String? = nil, shapedDisplayName: MFMString? = nil, shapedCw: MFMString? = nil, shapedNote: MFMString? = nil) {
            self.type = type
            self.owner = owner
            noteEntity = entity
            self.commentRNTarget = commentRNTarget
            self.renotee = renotee
            self.baseNoteId = baseNoteId
            self.shapedDisplayName = shapedDisplayName
            self.shapedCw = shapedCw
            self.shapedNote = shapedNote
        }
        
        // MARK: Statics
        
        static func fakeRenoteecell(renotee: String, renoteeUserName: String, baseNoteId: String) -> NoteCell.Model {
            var renotee = renotee
            if renotee.count > 7 {
                renotee = String(renotee.prefix(10)) + "..."
            }
            
            return NoteCell.Model(type: .renotee,
                                  owner: nil,
                                  entity: NoteEntity(username: renoteeUserName),
                                  renotee: renotee,
                                  baseNoteId: baseNoteId)
        }
        
        static func fakePromotioncell(baseNoteId: String) -> NoteCell.Model {
            return NoteCell.Model(type: .promote, owner: nil, baseNoteId: baseNoteId)
        }
        
        static func fakeSkeltonCell() -> NoteCell.Model {
            return NoteCell.Model(type: .skelton, owner: nil)
        }
    }
    
    enum ModelType {
        case model
        case skelton
        case promote
        case renotee
    }
    
    struct Section {
        var items: [Model]
    }
    
    class Reaction: CellModel {
        let entity: ReactionEntity
        
        init(from entity: ReactionEntity) {
            self.entity = entity
            let rawEmoji = entity.rawEmoji?.regexMatches(pattern: ":(.+)@.*:").map { $0[1] }
            if let rawEmoji = rawEmoji, !rawEmoji.isEmpty {
                self.entity.url = MisscatApi.name2emojis[rawEmoji[0]]?.url
            }
        }
        
        struct Section {
            var items: [Reaction]
        }
    }
}

extension NoteCell.Section: AnimatableSectionModelType {
    typealias Item = NoteCell.Model
    typealias Identity = String
    
    var identity: String {
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
    
    var identity: String {
        return ""
    }
    
    init(original: Item.Section, items: [Item]) {
        self = original
        self.items = items
    }
}

extension NoteCell.Model {
    /// ReactionCountをNoteCell.Reactionに変換する
    func getReactions(with externalEmojis: [EmojiModel?]?) -> [NoteCell.Reaction] {
        guard let owner = owner, let noteId = noteEntity.noteId else { return [] }
        
        return noteEntity.reactions.compactMap {
            ReactionEntity(from: $0, with: externalEmojis, myReaction: noteEntity.myReaction, noteId: noteId, owner: owner)
        }
        .compactMap {
            NoteCell.Reaction(from: $0)
        }
    }
}
