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
    
    func vote(choice: [Int], to noteId: String) {
        model.vote(choice: choice, to: noteId)
    }
    
    func renote(noteId: String) {
        model.renote(noteId: noteId)
    }
}
