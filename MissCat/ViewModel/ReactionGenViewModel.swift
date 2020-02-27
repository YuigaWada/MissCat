//
//  ReactionGenViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/18.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxSwift

class ReactionGenViewModel: ViewModelType {
    // MARK: I/O
    
    struct Input {}
    
    struct Output {
        let favorites: [ReactionGenViewController.EmojisSection] // 同期
        let otherEmojis: PublishSubject<[ReactionGenViewController.EmojisSection]> // 非同期
    }
    
    struct State {}
    
    //    private let input: Input
    public lazy var output: Output = {
        let presets = model.getPresets()
        let favorites = [ReactionGenViewController.EmojisSection(items: presets)]
        
        return .init(favorites: favorites,
                     otherEmojis: self.otherEmojis)
    }()
    
    private lazy var emojisList: [EmojiView.EmojiModel] = {
        [EmojiViewHeader(title: "Favorites")] + model.getPresets() // ヘッダーを追加する
    }()
    
    private let otherEmojis: PublishSubject<[ReactionGenViewController.EmojisSection]> = .init()
    
    public var dataSource: EmojisDataSource?
    public var targetNoteId: String?
    public var hasMarked: Bool { // リアクションが登録されているか?
        return myReaction != nil
    }
    
    private var myReaction: String?
    private let model = ReactionGenModel()
    private let disposeBag: DisposeBag
    
    private var isLoading: Bool = false
    
    init(and disposeBag: DisposeBag) {
        self.disposeBag = disposeBag
    }
    
    public func setEmojiModel(completion: (() -> Void)? = nil) {
        guard !isLoading else { return }
        
        model.getEmojiModel().subscribe(onNext: { emojis in
            self.isLoading = true
            
            self.emojisList.append(emojis)
            self.updateEmojis(self.emojisList)
            
            self.isLoading = false
            completion?()
        }).disposed(by: disposeBag)
    }
    
    public func checkHeader(index: Int) -> Bool {
        return emojisList[index] is EmojiViewHeader
    }
    
    public func registerReaction(noteId: String, reaction: String) {
        model.registerReaction(noteId: noteId, reaction: reaction) { success in
            guard success else { return }
            
            self.myReaction = reaction
        }
    }
    
    public func cancelReaction(noteId: String) {
        model.cancelReaction(noteId: noteId) { success in
            guard success else { return }
            
            self.myReaction = nil
        }
    }
    
    private func updateEmojis(_ items: [EmojiView.EmojiModel]) {
        let section = ReactionGenViewController.EmojisSection(items: items)
        updateEmojis(section)
    }
    
    private func updateEmojis(_ section: ReactionGenViewController.EmojisSection) {
        otherEmojis.onNext([section])
    }
}
