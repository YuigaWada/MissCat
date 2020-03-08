//
//  NotificationCellViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/24.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import UIKit

public class NotificationCellViewModel {
    private var model = NotificationCellModel()
    
    public func shapeNote(identifier: String, note: String, noteId: String, isReply: Bool, yanagi: YanagiText, externalEmojis: [EmojiModel?]?) -> NSAttributedString? {
        let cachedNote = Cache.shared.getNote(noteId: noteId) // セルが再利用されるのでキャッシュは中央集権的に
        let hasCachedNote: Bool = cachedNote != nil
        
        let treatedNote = model.shapeNote(identifier: identifier,
                                          note: note,
                                          cache: cachedNote,
                                          isReply: isReply,
                                          yanagi: yanagi,
                                          externalEmojis: externalEmojis)
        
        if !hasCachedNote, let treatedNote = treatedNote {
            Cache.shared.saveNote(noteId: noteId, note: treatedNote, attachments: yanagi.getAttachments()) // CACHE!
        }
        
        return treatedNote
    }
}
