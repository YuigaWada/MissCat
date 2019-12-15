//
//  ReactionGenModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/18.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxSwift

fileprivate typealias EmojiModel = ReactionGenViewController.EmojiModel
public class ReactionGenModel {
    
    //MARK: EMOJIS
    fileprivate static let fileShared: ReactionGenModel = .init(isFileShared: true) // 事前に詠み込んだ絵文字データを半永続化
    fileprivate class Emojis {
        var currentIndex: Int = 0
        var isLoading: Bool = false
        var preloaded: [ReactionGenViewController.EmojiModel] = [] //非同期で事前に詠み込んでおく
    }
    
    fileprivate class DefaultEmojis: Emojis {
        lazy var emojis = EmojiHandler.handler.defaultEmojis
    }
    
    fileprivate class CustomEmojis: Emojis {
        lazy var emojis = EmojiHandler.handler.customEmojis
    }
   
    //MARK: Private Vars
    private var defaultEmojis = DefaultEmojis()
    private var customEmojis = CustomEmojis()
    private var maxOnceLoad: Int = 50
    private var defaultPreset = ["👍","❤️","😆","🤔","😮","🎉","💢","😥","😇","🍮","⭐"]
    
    //MARK: Life Cycle
    init(isFileShared: Bool = false) {
        guard !isFileShared, ReactionGenModel.fileShared.defaultEmojis.currentIndex == 0 else { return }
        ReactionGenModel.fileShared.setNextDefaultEmojis() //事前に詠み込んでおく
    }
    
    //MARK: Public Methods
    //プリセットｎ絵文字を取得
    public func getPresets()-> [ReactionGenViewController.EmojiModel] {
        
        if !EmojiModel.checkSavedArray() {
            var emojiModels: [EmojiModel] = []
            self.defaultPreset.forEach { char in
                emojiModels.append(EmojiModel(isDefault: true,
                                              defaultEmoji: char,
                                              customEmojiUrl: nil))
            }
            EmojiModel.saveModelArray(with: emojiModels)
            return emojiModels
        }
        
        //UserDefaultsが存在したら...
        guard let emojiModels = EmojiModel.getModelArray() else { fatalError("Internal Error.") }

        return emojiModels
    }
    
    public func getNextDefaultEmojis()-> Observable<[ReactionGenViewController.EmojiModel]> {
        let dispose = Disposables.create()
       
        return Observable.create { [unowned self] observer in
            observer.onNext(ReactionGenModel.fileShared.defaultEmojis.preloaded)
            observer.onCompleted()
            
            self.setNextDefaultEmojis()
            return dispose
        }
    }

    public func getCustomEmojis()-> Observable<ReactionGenViewController.EmojiModel> {
        let dispose = Disposables.create()
        
        return Observable.create { [unowned self] observer in
            DispatchQueue.global(qos: .default).async {
//                guard let customEmojis = self.customEmojis else { return dispose }
//
//                customEmojis.forEach { emoji in
//                    guard let url = emoji.url else { return }
//
//                    observer.onNext(ReactionGenViewController.EmojiModel(isDefault: false,
//                                                                         defaultEmoji: nil,
//                                                                         customEmojiUrl: url))
//                }
            }
            return dispose
        }
    }
    
    
    
    public func registerReaction(noteId: String, reaction: String, completion: @escaping (Bool)->()) {
        MisskeyKit.notes.createReaction(noteId: noteId, reaction: reaction) { result, _ in
            completion(result)
        }
    }
    
    
    public func cancelReaction(noteId: String, completion: @escaping (Bool)->()) {
        MisskeyKit.notes.deleteReaction(noteId: noteId) { result, _ in
            completion(result)
        }
    }
    
    //MARK: Private Methods
    private func setNextDefaultEmojis() {
        guard let emojis = ReactionGenModel.fileShared.defaultEmojis.emojis else { return }
        
        DispatchQueue.global(qos: .default).async {
            let currentIndex = ReactionGenModel.fileShared.defaultEmojis.currentIndex
            
            ReactionGenModel.fileShared.defaultEmojis.currentIndex += self.maxOnceLoad
            for i in currentIndex ..< currentIndex + self.maxOnceLoad {
                let emoji = emojis[i]
                guard let char = emoji.char else { return }
                
                ReactionGenModel.fileShared.defaultEmojis.preloaded.append(ReactionGenViewController.EmojiModel(isDefault: true,
                                                                       defaultEmoji: char,
                                                                       customEmojiUrl: nil))
            }

        }
        
    }
    
    
}
