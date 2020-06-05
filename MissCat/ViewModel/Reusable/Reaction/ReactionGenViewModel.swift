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
        let owner: SecureUser
        let searchTrigger: Observable<String>
    }
    
    struct Output {
        let emojis: PublishSubject<[ReactionGenViewController.EmojisSection]> = .init()
    }
    
    struct State {}
    
    private let input: Input
    lazy var output: Output = .init()
    
    private lazy var emojisList: [EmojiView.EmojiModel] = {
        var history = model.getHistoryEmojis()
        let favs = [EmojiViewHeader(title: "Favorites")] + model.getFavEmojis()
        
        let hasHistory = history.count > 0
        history = hasHistory ? [EmojiViewHeader(title: "History")] + history : []
        
        return favs + history
    }()
    
    private var searched: [EmojiView.EmojiModel] = []
    
    var dataSource: EmojisDataSource?
    var targetNoteId: String?
    var hasMarked: Bool { // リアクションが登録されているか?
        return myReaction != nil
    }
    
    private var myReaction: String?
    
    private lazy var misskey: MisskeyKit? = MisskeyKit(from: input.owner)
    private lazy var model = ReactionGenModel(from: misskey)
    private let disposeBag: DisposeBag
    
    init(with input: Input, and disposeBag: DisposeBag) {
        self.input = input
        self.disposeBag = disposeBag
        
        binding()
    }
    
    // MARK: Publics
    
    func setEmojiModel(completion: (() -> Void)? = nil) {
        model.getEmojiModel().subscribe(onNext: { emojis in
            self.emojisList.append(emojis)
            self.updateEmojis(self.emojisList)
            completion?()
        }).disposed(by: disposeBag)
    }
    
    func checkHeader(index: Int) -> Bool {
        guard searched.count == 0 else { return false } // 検索時はヘッダーなし
        return emojisList[index] is EmojiViewHeader
    }
    
    func registerReaction(noteId: String, emojiModel: EmojiView.EmojiModel) {
        guard let reaction = emojiModel.isDefault ? emojiModel.defaultEmoji : ":" + emojiModel.rawEmoji + ":" else { return }
        
        model.registerReaction(noteId: noteId, reaction: reaction, emojiModel: emojiModel) { success in
            guard success else { return }
            self.myReaction = reaction
        }
    }
    
    func cancelReaction(noteId: String) {
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
        
        searched = emojisList.filter {
            if text.count == 1, let emoji = $0.defaultEmoji { // デフォルト絵文字を検索
                return emoji == text
            }
            return String($0.rawEmoji.prefix(target.count)) == target
        }
        updateEmojis(searched)
    }
    
    private func updateEmojis(_ items: [EmojiView.EmojiModel]) {
        let section = ReactionGenViewController.EmojisSection(items: items)
        updateEmojis(section)
    }
    
    private func updateEmojis(_ section: ReactionGenViewController.EmojisSection) {
        output.emojis.onNext([section])
    }
}
