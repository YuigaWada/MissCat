//
//  NoteCellViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/19.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit
import MisskeyKit

public class NoteCellViewModel {
    
    private var model = NoteCellModel()    

    public func shapeNote(identifier: String, note: String, cache: NSAttributedString?,isReply: Bool, externalEmojis: [EmojiModel?]?, isDetailMode: Bool)-> NSAttributedString? {
        let treatedNote = model.shapeNote(cache: cache,
                                          identifier: identifier,
                                          note: note,
                                          isReply: isReply,
                                          externalEmojis: externalEmojis,
                                          isDetailMode: isDetailMode)
        
        return treatedNote
    }
    
    public func registerReaction(noteId: String, reaction: String) {
        model.registerReaction(noteId: noteId, reaction: reaction)
    }
    
    public func cancelReaction(noteId: String){
        model.cancelReaction(noteId: noteId)
    }
}
