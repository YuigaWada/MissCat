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
    
    public func getNoteCellModel(withRN: Bool = false) -> NoteCell.Model? {
        guard let user = post.user else { return nil }
        
//        var reactions: [Any?] = []
        let displayName = (user.name ?? "") == "" ? user.username : user.name // user.nameがnilか""ならusernameで代替
        
//        (post.reactions ?? []).forEach { reaction in
//            guard let reaction = reaction else { return }
//
//            let emoji = EmojiHandler.handler.encodeEmoji(raw: reaction.name!)
//            reactions.append(emoji)
//        }
//
        let emojis = (post.emojis ?? []) + (user.emojis ?? []) // 絵文字情報を統合する
        
        var cellModel = NoteCell.Model(noteId: post.id,
                                       iconImageUrl: user.avatarUrl,
                                       userId: user.id,
                                       displayName: displayName ?? "",
                                       username: user.username ?? "",
                                       note: post.text?.mfmPreTransform() ?? "", // MFMEngineを通して加工の前処理をしておく
                                       ago: post.createdAt!,
                                       replyCount: post.repliesCount ?? 0,
                                       renoteCount: post.renoteCount ?? 0,
                                       reactions: post.reactions?.compactMap { $0 } ?? [],
                                       shapedReactions: [],
                                       myReaction: post.myReaction,
                                       files: post.files?.compactMap { $0 } ?? [],
                                       emojis: emojis.compactMap { $0 },
                                       poll: post.poll)
        
        cellModel.shapedReactions = cellModel.getReactions()
        cellModel.isReply = post.reply != nil
        return cellModel
    }
}
