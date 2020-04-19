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
    func getNoteCellModel(withRN: Bool = false, onOtherNote: Bool = false) -> NoteCell.Model? {
        guard let user = post.user else { return nil }
        
        let displayName = (user.name ?? "") == "" ? user.username : user.name // user.nameがnilか""ならusernameで代替
        let emojis = (post.emojis ?? []) + (user.emojis ?? []) // 絵文字情報を統合する
        
        let cellModel = NoteCell.Model(noteId: post.id,
                                       iconImageUrl: user.avatarUrl,
                                       userId: user.id,
                                       displayName: displayName ?? "",
                                       username: user.username ?? "",
                                       hostInstance: user.host ?? "",
                                       note: post.text?.mfmPreTransform() ?? "", // MFMEngineを通して加工の前処理をしておく
                                       ago: post.createdAt!,
                                       replyCount: post.repliesCount ?? 0,
                                       renoteCount: post.renoteCount ?? 0,
                                       reactions: post.reactions?.compactMap { $0 } ?? [],
                                       shapedReactions: [],
                                       myReaction: post.myReaction,
                                       files: post.files?.compactMap { $0 } ?? [],
                                       emojis: emojis.compactMap { $0 },
                                       commentRNTarget: withRN ? post.renote?.getNoteCellModel(onOtherNote: true) ?? nil : nil,
                                       original: self,
                                       onOtherNote: onOtherNote,
                                       poll: post.poll,
                                       cw: post.cw)
        
        cellModel.shapedReactions = cellModel.getReactions(with: emojis)
        cellModel.isReply = post.reply != nil
        return cellModel
    }
}
