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
        MisskeyKit.notes.createReaction(noteId: noteId, reaction: reaction) { _, _ in
//            print("registerReaction: [result: \(result), error: \(error)]")
        }
    }
    
    public func cancelReaction(noteId: String) {
        MisskeyKit.notes.deleteReaction(noteId: noteId) { _, _ in
//            print("cancelReaction: [result: \(result), error: \(error)]")
        }
    }
}
