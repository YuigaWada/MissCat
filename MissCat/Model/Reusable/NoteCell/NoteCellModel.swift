//
//  NoteCellModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/19.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation
import MisskeyKit

class NoteCellModel {
    private let misskey: MisskeyKit?
    init(from misskey: MisskeyKit?) {
        self.misskey = misskey
    }
    
    func registerReaction(noteId: String, reaction: String) {
        misskey?.notes.createReaction(noteId: noteId, reaction: reaction) { _, _ in
//            print("registerReaction: [result: \(result), error: \(error)]")
        }
    }
    
    func cancelReaction(noteId: String) {
        misskey?.notes.deleteReaction(noteId: noteId) { _, _ in
//            print("cancelReaction: [result: \(result), error: \(error)]")
        }
    }
}
