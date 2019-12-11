//
//  NoteModel+MissCat.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/25.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit

extension NoteModel {
    public func getNoteCellModel()-> NoteCell.Model? {
        let post = self
        
        guard let user = post.user else { return nil }
        
        var reactions: [Any?] = []
        let displayName = (user.name ?? "") == "" ? user.username : user.name // user.nameがnilか""ならusernameで代替
        
        (post.reactions ?? []).forEach{ reaction in
            guard let reaction = reaction else { return }
            
            let emoji = EmojiHandler.handler.encodeEmoji(raw: reaction.name!)
            reactions.append(emoji)
        }
        
        var cellModel = NoteCell.Model(noteId: post.id,
                                       iconImageUrl: user.avatarUrl,
                                       userId: user.id,
                                       displayName: displayName ?? "",
                                       username: user.username ?? "",
                                       note: post.text ?? "",
                                       ago: post.createdAt!,
                                       replyCount: post.repliesCount ?? 0,
                                       renoteCount: post.renoteCount ?? 0,
                                       reactions: post.reactions ?? [],
                                       myReaction: post.myReaction,
                                       files: post.files ?? [],
                                       emojis: (post.emojis ?? []).filter({$0 != nil}))
        
        
        cellModel.isReply = post.reply != nil
        
        return cellModel
    }
}
