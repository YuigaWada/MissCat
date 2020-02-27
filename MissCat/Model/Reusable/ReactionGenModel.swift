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
        
        lazy var categorizedDefault = EmojiHandler.handler.categorizedDefaultEmojis
        lazy var categorizedCustom = EmojiHandler.handler.categorizedCustomEmojis
    }
    
    fileprivate lazy var presetEmojiModels = EmojiModel.getModelArray()
    
    // MARK: Private Vars
    
    private var emojis = Emojis()
    private var maxOnceLoad: Int = 50
    private var defaultPreset = ["👍"]
    
    private var defaultLoaded = false
    
    // MARK: Life Cycle
    
    init(isFileShared: Bool = false) { }
    
    // MARK: Public Methods
    
    // プリセットｎ絵文字を取得
    public func getPresets() -> [EmojiView.EmojiModel] {
        guard EmojiModel.hasUserDefaultsEmojis else { // UserDefaultsが存在しないならUserDefaultsセットしておく
            var emojiModels: [EmojiModel] = []
            defaultPreset.forEach { char in
                emojiModels.append(EmojiModel(rawEmoji: char,
                                              isDefault: true,
                                              defaultEmoji: char,
                                              customEmojiUrl: nil))
            }
            fakeCellPadding(array: &emojiModels, count: defaultPreset.count)
            EmojiModel.saveModelArray(with: emojiModels)
            return emojiModels
        }
        
        // UserDefaultsが存在したら...
        guard ReactionGenModel.fileShared.presetEmojiModels != nil else { fatalError("Internal Error.") }
        
        var emojiModels = ReactionGenModel.fileShared.presetEmojiModels!
        fakeCellPadding(array: &emojiModels, count: emojiModels.count)
        return emojiModels
    }
    
    public func getEmojiModel() -> Observable<EmojiView.EmojiModel> {
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
