//
//  NoteCellModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/19.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation
import MisskeyKit

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
    public func shapeNote(cache: NSAttributedString?, identifier: String, note: String, isReply: Bool, externalEmojis: [EmojiModel?]?, isDetailMode: Bool)-> NSAttributedString? {
        if !isDetailMode, let cache = cache { //詳細モードの場合はキャッシュを利用しない
            return cache
        }
        let replyHeader: NSMutableAttributedString = isReply ? .getReplyMark() : .init() //リプライの場合は先頭にreplyマークつける
        let attributedText: NSMutableAttributedString = .init(attributedString: replyHeader)
        
        let newNote = note.shapeForMFM(externalEmojis: externalEmojis)
        attributedText.append(newNote.toAttributedString(family: "Helvetica", size: isDetailMode ? 14.0 : 11.0) ?? .init())
        
        return attributedText
    }
}
