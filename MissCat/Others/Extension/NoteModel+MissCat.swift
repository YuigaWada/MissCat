//
//  NoteModel+MissCat.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/25.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit

extension NoteModel {
    fileprivate var post: NoteModel { return self }
    
    var isFeatured: Bool { return post._featuredId_ != nil }
    var isPr: Bool { return post._prId_ != nil }
    /// おすすめノートかどうか
    var isRecommended: Bool { return post._featuredId_ != nil || post._prId_ != nil }
    
    /// NoteModelをNoteCell.Modelに変換する
    /// - Parameters:
    ///   - withRN: 引用RNかどうか
    ///   - onOtherNote: 何らかの形で、別の投稿の上に載ってる投稿か
    func getNoteCellModel(owner: SecureUser?, withRN: Bool = false, onOtherNote: Bool = false) -> NoteCell.Model? {
        guard let user = post.user else { return nil }
        
        let displayName = (user.name ?? "") == "" ? user.username : user.name // user.nameがnilか""ならusernameで代替
        let emojis = (EmojiModel.convert(from: post.emojis) ?? []) + (EmojiModel.convert(from: user.emojis) ?? []) // 絵文字情報を統合する
        
        let entity = NoteEntity(noteId: post.id,
                                iconImageUrl: user.avatarUrl,
                                isCat: user.isCat ?? false,
                                userId: user.id,
                                displayName: displayName ?? "",
                                username: user.username ?? "",
                                hostInstance: user.host ?? owner?.instance ?? "", // 同じインスタンスのユーザーはhostがnilになるので追加しておく
                                note: post.text?.mfmPreTransform() ?? "", // MFMEngineを通して加工の前処理をしておく
                                ago: post.createdAt!,
                                replyCount: post.repliesCount ?? 0,
                                renoteCount: post.renoteCount ?? 0,
                                reactions: post.reactions?.compactMap { $0 } ?? [],
                                shapedReactions: [],
                                myReaction: post.myReaction,
                                files: post.files?.compactMap { $0 } ?? [],
                                emojis: emojis.compactMap { $0 },
                                original: self,
                                onOtherNote: onOtherNote,
                                poll: post.poll,
                                cw: post.cw)
        
        let commentRNTarget = withRN ? post.renote?.getNoteCellModel(owner: owner, onOtherNote: true) ?? nil : nil
        let cellModel = NoteCell.Model(owner: owner,
                                       entity: entity,
                                       commentRNTarget: commentRNTarget)
        
        cellModel.shapedReactions = cellModel.getReactions(with: emojis) // ココ
        cellModel.isReply = post.reply != nil
        return cellModel
    }
}
