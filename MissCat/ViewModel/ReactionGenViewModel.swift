//
//  ReactionGenViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/18.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import RxSwift
import MisskeyKit

class ReactionGenViewModel: ViewModelType {
    
    
    //MARK: I/O
    struct Input {
        
    }
    
    struct Output {
        let favorites: [ReactionGenViewController.EmojisSection] // 同期
        let otherEmojis: PublishSubject<[ReactionGenViewController.EmojisSection]> // 非同期
    }
    
    struct State {
        
    }
    
    //    private let input: Input
    public lazy var output: Output = {
        let presets = model.getPresets()
        let favorites = [ReactionGenViewController.EmojisSection(items: presets)]
        
        return .init(favorites: favorites,
                     otherEmojis: self.otherEmojis)
    }()
    
    private var otherEmojisList: [ReactionGenViewController.EmojiModel] = []
    private let otherEmojis: PublishSubject<[ReactionGenViewController.EmojisSection]> = .init()
    
    
    
    public var dataSource: EmojisDataSource?
    public var targetNoteId: String?
    public var hasMarked: Bool { //リアクションが登録されているか?
        return self.myReaction != nil
    }
    
    
    private var myReaction: String?
    private let model = ReactionGenModel()
    private let disposeBag: DisposeBag
    
    private var isLoading: Bool = false
    
    init(and disposeBag: DisposeBag) { //init(with input: Input, and disposeBag: DisposeBag) {
        //        self.input = input
        self.disposeBag = disposeBag
    }
    
    public func getNextEmojis() {
        guard !self.isLoading else { return }
        
        self.model.getNextDefaultEmojis().subscribe(onNext: { emojis in
            self.isLoading = true
            
//            self.otherEmojisList.append(emojis)
            
            let section = ReactionGenViewController.EmojisSection(items: emojis)
            self.otherEmojis.onNext([section])
            
            self.isLoading = false
        }).disposed(by: disposeBag)
        
//        self.model.getCustomEmojis().subscribe(onNext: { emojis in
//            self.otherEmojisList.append(emojis)
//
//            let section = ReactionGenViewController.EmojisSection(items: self.otherEmojisList)
//            self.otherEmojis.onNext([section])
//        }).disposed(by: disposeBag)
    }
    
    
    public func registerReaction(noteId: String, reaction: String) {
        model.registerReaction(noteId: noteId, reaction: reaction) { success in
            guard success else { return }
            
            self.myReaction = reaction
        }
    }
    
    
    public func cancelReaction(noteId: String){
        model.cancelReaction(noteId: noteId) { success in
            guard success else { return }
            
            self.myReaction = nil
        }
    }
    
    
    
}
