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
class ReactionGenModel {
    // MARK: EMOJIS
    
    fileprivate static let fileShared: ReactionGenModel = .init(isFileShared: true) // 事前に詠み込んだ絵文字データを半永続化
    fileprivate class Emojis {
        var currentIndex: Int = 0
        var isLoading: Bool = false
        var preloaded: [EmojiView.EmojiModel] = [] // 非同期で事前に詠み込んでおく
        
        lazy var categorizedDefault = EmojiHandler.handler.categorizedDefaultEmojis
        lazy var categorizedCustom = EmojiHandler.handler.categorizedCustomEmojis
    }
    
    fileprivate lazy var favEmojiModels = EmojiModel.getEmojis(type: .favs)
    fileprivate lazy var historyEmojis = EmojiModel.getEmojis(type: .history)
    
    // MARK: Private Vars
    
    private var emojis = Emojis()
    private var maxOnceLoad: Int = 50
    private var defaultPreset = ["👍", "❤️", "😆", "🤔", "😮", "🎉", "💢", "😥", "😇", "🍮", "🤯"]
    private var defaultLoaded = false
    
    // MARK: Life Cycle
    
    init(isFileShared: Bool = false) {}
    
    // MARK: Public Methods
    
    func getFavEmojis() -> [EmojiView.EmojiModel] {
        guard EmojiModel.hasFavEmojis else { // UserDefaultsが存在しないならUserDefaultsセットしておく
            var emojiModels: [EmojiModel] = []
            defaultPreset.forEach { char in
                emojiModels.append(EmojiModel(rawEmoji: char,
                                              isDefault: true,
                                              defaultEmoji: char,
                                              customEmojiUrl: nil))
            }
            
            EmojiModel.saveEmojis(with: emojiModels, type: .favs)
            fakeCellPadding(array: &emojiModels, count: defaultPreset.count)
            
            return emojiModels
        }
        
        // UserDefaultsが存在したら...
        guard ReactionGenModel.fileShared.favEmojiModels != nil else { return [] }
        
        var emojiModels = ReactionGenModel.fileShared.favEmojiModels!
        fakeCellPadding(array: &emojiModels, count: emojiModels.count)
        return emojiModels
    }
    
    func getHistoryEmojis() -> [EmojiView.EmojiModel] {
        guard EmojiModel.hasHistory, ReactionGenModel.fileShared.historyEmojis != nil else { return [] }
        
        var historyEmojis = ReactionGenModel.fileShared.historyEmojis!
        fakeCellPadding(array: &historyEmojis, count: historyEmojis.count)
        return historyEmojis
    }
    
    func getEmojiModel() -> Observable<EmojiView.EmojiModel> {
        let dispose = Disposables.create()
        
        return Observable.create { [unowned self] observer in
            // カスタム→デフォルトの順に表示したいので、この順に取り出していく
            for categorized in [self.emojis.categorizedCustom, self.emojis.categorizedDefault] {
                categorized.forEach { category, emojiModels in // カテゴリーによってセクションを切り分ける(擬似的にヘッダーを作る)
                    observer.onNext(EmojiViewHeader(title: category)) // 疑似ヘッダーのモデル
                    emojiModels.forEach { observer.onNext($0) }
                    
                    self.fakeCellPadding(observer: observer, count: emojiModels.count)
                }
            }
            return dispose
        }
    }
    
    func registerReaction(noteId: String, reaction: String, emojiModel: EmojiView.EmojiModel, completion: @escaping (Bool) -> Void) {
        saveHistory(emojiModel) // リアクションの履歴を保存
        MisskeyKit.notes.createReaction(noteId: noteId, reaction: reaction) { result, _ in
            completion(result)
        }
    }
    
    func cancelReaction(noteId: String, completion: @escaping (Bool) -> Void) {
        MisskeyKit.notes.deleteReaction(noteId: noteId) { result, _ in
            completion(result)
        }
    }
    
    // MARK: Private Methods
    
    /// CollectionViewのセルが左詰めになるように、空いた部分を空のセルでパディングしていく
    /// - Parameters:
    ///   - observer: Observer
    ///   - count: もともと表示させたいセルの数
    private func fakeCellPadding(observer: RxSwift.AnyObserver<EmojiView.EmojiModel>, count: Int) {
        if count % 7 != 0 {
            for _ in 0 ..< 7 - (count % 7) {
                observer.onNext(EmojiView.EmojiModel(rawEmoji: "", // ** FAKE **
                                                     isDefault: false,
                                                     defaultEmoji: "",
                                                     customEmojiUrl: nil,
                                                     isFake: true))
            }
        }
    }
    
    /// CollectionViewのセルが左詰めになるように、空いた部分を空のセルでパディングしていく
    /// - Parameters:
    ///   - array: Array
    ///   - count: もともと表示させたいセルの数
    private func fakeCellPadding(array: inout [EmojiView.EmojiModel], count: Int) {
        if count % 7 != 0 {
            for _ in 0 ..< 7 - (count % 7) {
                array.append(EmojiView.EmojiModel(rawEmoji: "", // ** FAKE **
                                                  isDefault: false,
                                                  defaultEmoji: "",
                                                  customEmojiUrl: nil,
                                                  isFake: true))
            }
        }
    }
    
    /// リアクションの履歴を保存
    /// - Parameter emojiModel: EmojiView.EmojiModel
    private func saveHistory(_ emojiModel: EmojiView.EmojiModel) {
        guard ReactionGenModel.fileShared.historyEmojis != nil else {
            ReactionGenModel.fileShared.historyEmojis = [emojiModel]
            return
        }
        
        // 重複する分とpaddingのためのフェイクは除く
        var history = ReactionGenModel.fileShared.historyEmojis!.filter { !$0.isFake && $0.rawEmoji != emojiModel.rawEmoji }
        if history.count > 7 * 2 { // 2行分だけ表示させる
            history.removeLast()
        }
        
        history.insert(emojiModel, at: 0)
        EmojiModel.saveEmojis(with: history, type: .history)
        ReactionGenModel.fileShared.historyEmojis = history
    }
}

// MARK: ReactionGenCell.Model

extension ReactionGenViewController {
    struct EmojisSection {
        var items: [Item]
    }
}

extension ReactionGenViewController.EmojisSection: SectionModelType {
    typealias Item = EmojiView.EmojiModel
    
    init(original: ReactionGenViewController.EmojisSection, items: [Item]) {
        self = original
        self.items = items
    }
}
