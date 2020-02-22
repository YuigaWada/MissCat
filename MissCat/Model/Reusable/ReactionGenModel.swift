//
//  ReactionGenModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/18.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxDataSources
import RxSwift

private typealias EmojiModel = EmojiView.EmojiModel
public class ReactionGenModel {
    // MARK: EMOJIS
    
    fileprivate static let fileShared: ReactionGenModel = .init(isFileShared: true) // 事前に詠み込んだ絵文字データを半永続化
    fileprivate class Emojis {
        var currentIndex: Int = 0
        var isLoading: Bool = false
        var preloaded: [EmojiView.EmojiModel] = [] // 非同期で事前に詠み込んでおく
    }
    
    fileprivate class DefaultEmojis: Emojis {
        lazy var emojis = EmojiHandler.handler.defaultEmojis
    }
    
    fileprivate class CustomEmojis: Emojis {
        lazy var emojis = EmojiHandler.handler.customEmojis
    }
    
    fileprivate lazy var presetEmojiModels = EmojiModel.getModelArray()
    
    // MARK: Private Vars
    
    private var defaultEmojis = DefaultEmojis()
    private var customEmojis = CustomEmojis()
    private var maxOnceLoad: Int = 50
    private var defaultPreset = ["👍"]
    
    private var defaultLoaded = false
    
    // MARK: Life Cycle
    
    init(isFileShared: Bool = false) {
        guard !isFileShared, ReactionGenModel.fileShared.defaultEmojis.currentIndex == 0 else { return }
        ReactionGenModel.fileShared.setNextDefaultEmojis() // 事前に詠み込んでおく
    }
    
    // MARK: Public Methods
    
    // プリセットｎ絵文字を取得
    public func getPresets() -> [EmojiView.EmojiModel] {
        guard EmojiModel.checkSavedArray() else { // UserDefaultsが存在しないならUserDefaultsセットしておく
            var emojiModels: [EmojiModel] = []
            defaultPreset.forEach { char in
                emojiModels.append(EmojiModel(rawEmoji: char,
                                              isDefault: true,
                                              defaultEmoji: char,
                                              customEmojiUrl: nil))
            }
            EmojiModel.saveModelArray(with: emojiModels)
            return emojiModels
        }
        
        // UserDefaultsが存在したら...
        guard let emojiModels = ReactionGenModel.fileShared.presetEmojiModels else { fatalError("Internal Error.") }
        return emojiModels
    }
    
    public func getNextDefaultEmojis() -> Observable<[EmojiView.EmojiModel]> {
        let dispose = Disposables.create()
        
        return Observable.create { [unowned self] observer in
            observer.onNext(ReactionGenModel.fileShared.defaultEmojis.preloaded)
            observer.onCompleted()
            
            if !self.defaultLoaded {
                self.defaultLoaded = !self.setNextDefaultEmojis()
            }
            return dispose
        }
    }
    
    public func getCustomEmojis() -> Observable<EmojiView.EmojiModel> {
        let dispose = Disposables.create()
        
        return Observable.create { [unowned self] observer in
            guard let emojis = self.customEmojis.emojis else { return dispose }
            
            emojis.forEach { emoji in
                guard let url = emoji.url, let raw = emoji.name else { return }
                observer.onNext(EmojiView.EmojiModel(rawEmoji: raw,
                                                     isDefault: false,
                                                     defaultEmoji: nil,
                                                     customEmojiUrl: url))
            }
            return dispose
        }
    }
    
    public func registerReaction(noteId: String, reaction: String, completion: @escaping (Bool) -> Void) {
        MisskeyKit.notes.createReaction(noteId: noteId, reaction: reaction) { result, _ in
            completion(result)
        }
    }
    
    public func cancelReaction(noteId: String, completion: @escaping (Bool) -> Void) {
        MisskeyKit.notes.deleteReaction(noteId: noteId) { result, _ in
            completion(result)
        }
    }
    
    // MARK: Private Methods
    
    private func setNextDefaultEmojis() -> Bool {
        guard let emojis = ReactionGenModel.fileShared.defaultEmojis.emojis else { return false }
        
        emojis.forEach { emoji in
            guard let char = emoji.char else { return }
            
            ReactionGenModel.fileShared.defaultEmojis.preloaded.append(EmojiView.EmojiModel(rawEmoji: char,
                                                                                            isDefault: true,
                                                                                            defaultEmoji: char,
                                                                                            customEmojiUrl: nil))
        }
        
        return true
    }
}

// MARK: ReactionGenCell.Model

public extension ReactionGenViewController {
    struct EmojisSection {
        public var items: [Item]
    }
}

extension ReactionGenViewController.EmojisSection: SectionModelType {
    public typealias Item = EmojiView.EmojiModel
    
    public init(original: ReactionGenViewController.EmojisSection, items: [Item]) {
        self = original
        self.items = items
    }
}
