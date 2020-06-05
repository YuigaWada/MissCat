//
//  HomeModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/26.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit

class HomeModel {
    private let misskey: MisskeyKit?
    init(from misskey: MisskeyKit?) {
        self.misskey = misskey
    }
    
    
    func vote(choice: [Int], to noteId: String) {
        choice.forEach {
            self.misskey?.notes.vote(noteId: noteId, choice: $0, result: { _, _ in
                //            print(error)
            })
        }
    }
    
    func renote(noteId: String) {
        self.misskey?.notes.renote(renoteId: noteId) { _, _ in
            //            print(error)
        }
    }
}
