//
//  ReactionGenViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/18.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import RxSwift
import MisskeyKit

public class ReactionGenViewModel {
    public let emojis: PublishSubject<[ReactionGenViewController.EmojisSection]> = .init()
    public var dataSource: EmojisDataSource?
    public var targetNoteId: String?
    public var hasMarked: Bool { //リアクションが登録されているか?
        return self.myReaction != nil
    }
    
    
    private var myReaction: String?
    private let model = ReactionGenModel()
    //    private var emojisModel: [ReactionGenViewController.EmojiModel] = []
    
    
    
    public func getPresets()-> [ReactionGenViewController.EmojisSection] {
        let presets = model.getPresets()
        
        return [ReactionGenViewController.EmojisSection(items: presets)]
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
    
    
    
    
    init(disposeBag: DisposeBag) {
        let presets = model.getPresets()
        
        self.updateEmojis(new: [ReactionGenViewController.EmojisSection(items: presets)])
    }
    
    private func updateEmojis(new: [ReactionGenViewController.EmojisSection]) {
        self.emojis.onNext(new)
    }
    
}
