//
//  NotificationCellViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/24.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//


import UIKit
import MisskeyKit

public class NotificationCellViewModel {
    
    private var model = NotificationCellModel()
    
    public func shapeNote(identifier: String, note: String, isReply: Bool, externalEmojis: [EmojiModel?]?)-> NSAttributedString? {
        let treatedNote = model.shapeNote(identifier: identifier,
                                          note: note,
                                          isReply: isReply,
                                          externalEmojis: externalEmojis)
        
        return treatedNote
    }
    
}
