//
//  HomeModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/26.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit

class HomeModel {
    func vote(choice: [Int], to noteId: String, owner: SecureUser) {
        guard let misskey = MisskeyKit(from: owner) else { return }
        choice.forEach {
            misskey.notes.vote(noteId: noteId, choice: $0, result: { _, _ in
                //            print(error)
            })
        }
    }
    
    func renote(noteId: String, owner: SecureUser) {
        guard let misskey = MisskeyKit(from: owner) else { return }
        misskey.notes.renote(renoteId: noteId) { _, _ in
            //            print(error)
        }
    }
}
