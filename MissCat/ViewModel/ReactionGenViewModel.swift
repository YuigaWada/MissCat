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
    
    struct Input {
        let searchTrigger: Observable<String>
    }
    
    struct Output {
        let favorites: [ReactionGenViewController.EmojisSection] // 同期
        let otherEmojis: PublishSubject<[ReactionGenViewController.EmojisSection]> // 非同期
    }
    
    struct State {}
    
    private let input: Input
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
    
    private var searched: [EmojiView.EmojiModel] = []
    
    public var dataSource: EmojisDataSource?
    public var targetNoteId: String?
    public var hasMarked: Bool { // リアクションが登録されているか?
        return myReaction != nil
    }
    
    private var myReaction: String?
    private let model = ReactionGenModel()
    private let disposeBag: DisposeBag
    
    private var isLoading: Bool = false
    
    init(with input: Input, and disposeBag: DisposeBag) {
        self.input = input
        self.disposeBag = disposeBag
        
        binding()
    }
    
    // MARK: Publics
    
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
        guard searched.count == 0 else { return false } // 検索時はヘッダーなし
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
    
    // MARK: Privates
    
    private func binding() {
        input.searchTrigger.subscribe(onNext: { text in
            if text.isEmpty {
                self.searched = []
                self.updateEmojis(self.emojisList)
                return
            }
            
            self.searchEmojis(text)
        }).disposed(by: disposeBag)
    }
    
    private func searchEmojis(_ text: String) {
        guard text != ":", text != "::" else { return }
        let hasHeadColon = text.prefix(1) == ":"
        let hasTailColon = text.suffix(1) == ":"
        
        var target = text
        if hasTailColon {
            target = String(target.prefix(target.count - 1))
        }
        
        if hasHeadColon {
            target = String(target.suffix(target.count - 1))
        }
        
        searched = emojisList.filter { String($0.rawEmoji.prefix(target.count)) == target }
        updateEmojis(searched)
    }
    
    private func updateEmojis(_ items: [EmojiView.EmojiModel]) {
        let section = ReactionGenViewController.EmojisSection(items: items)
        updateEmojis(section)
    }
    
    private func updateEmojis(_ section: ReactionGenViewController.EmojisSection) {
        otherEmojis.onNext([section])
    }
}
