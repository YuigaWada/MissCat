//
//  HomeViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/26.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Foundation

class HomeViewModel: ViewModelType {
    struct Input {}
    struct Output {}
    struct State {}
    
    private let model = HomeModel()
    
    func vote(choice: [Int], to noteId: String, owner: SecureUser) {
        model.vote(choice: choice, to: noteId, owner: owner)
    }
    
    func renote(noteId: String, owner: SecureUser) {
        model.renote(noteId: noteId, owner: owner)
    }
}
