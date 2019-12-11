//
//  ReactionGenModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/18.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit


public class ReactionGenModel {
    
    //プリセットｎ絵文字を取得
    public func getPresets()-> [ReactionGenViewController.EmojiModel] {
        
        var emojis: [ReactionGenViewController.EmojiModel] = []
        for char in ["👍","❤️","😆","🤔","😮","🎉","💢","😥","😇","🍮","⭐"] {
            emojis.append(ReactionGenViewController.EmojiModel(isDefault: true,
                                                     defaultEmoji: char,
                                                     customEmojiUrl: nil))
        }
        
        return emojis
    }
    
    
    
    public func registerReaction(noteId: String, reaction: String, completion: @escaping (Bool)->()) {
         MisskeyKit.notes.createReaction(noteId: noteId, reaction: reaction) { result, error in
//            print("registerReaction: [result: \(result), error: \(error?.localizedDescription)]")
            completion(result)
         }
     }
    
    
    public func cancelReaction(noteId: String, completion: @escaping (Bool)->()) {
        MisskeyKit.notes.deleteReaction(noteId: noteId) { result, error in
//            print("cancelReaction: [result: \(result), error: \(error?.localizedDescription)]")
            completion(result)
        }
    }
    
    
}
