//
//  NoteCellModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/19.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation
import MisskeyKit
import YanagiText

public class NoteCellModel {
    
    public func registerReaction(noteId: String, reaction: String) {
        MisskeyKit.notes.createReaction(noteId: noteId, reaction: reaction) { result, error in
//            print("registerReaction: [result: \(result), error: \(error)]")
        }
    }
    
    
    public func cancelReaction(noteId: String){
        MisskeyKit.notes.deleteReaction(noteId: noteId) { result, error in
//            print("cancelReaction: [result: \(result), error: \(error)]")
        }
    }
    
    
    
    // ノートにHyperLink/css修飾を加え整形する
    public func shapeNote(cache: Cache.Note?, identifier: String, note: String, isReply: Bool, externalEmojis: [EmojiModel?]?, isDetailMode: Bool, yanagi: YanagiText)-> NSAttributedString? {
        if !isDetailMode, let cache = cache { //詳細モードの場合はキャッシュを利用しない
            
            // YanagiText内部ではattributedTextがsetされた瞬間attachmentの表示が始まるので先にaddしておく
            cache.attachments.forEach { nsAttachment, yanagiAttachment in
                yanagi.addAttachment(ns: nsAttachment, yanagi: yanagiAttachment)
            }
            
            return cache.treatedNote
        }
        let replyHeader: NSMutableAttributedString = isReply ? .getReplyMark() : .init() //リプライの場合は先頭にreplyマークつける
        let body = note.mfmTransform(yanagi: yanagi, externalEmojis: externalEmojis) ?? .init()
        
        return replyHeader + body
    }
}



