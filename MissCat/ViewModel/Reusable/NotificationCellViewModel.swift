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
    
    public func shapeNote(note: String, isReply: Bool) -> NSAttributedString? {
        let treatedNote = model.shapeNote(note: note, isReply: isReply)
        
        return treatedNote
    }
}
