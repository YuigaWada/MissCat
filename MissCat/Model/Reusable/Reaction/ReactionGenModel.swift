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

private typealias Repository = EmojiRepository
class EmojiRepository {
    enum Kind {
        case history
        case favs
    }
    
    struct UserEmojis {
        let owner: SecureUser
        var favs: [EmojiView.EmojiModel]
        var history: [EmojiView.EmojiModel]
    }
    
    static var shared: EmojiRepository = .init()
    
    var userEmojisList: [UserEmojis] = []
    
    func getUserEmojis(of kind: Kind, owner: SecureUser) -> [EmojiView.EmojiModel] {
        let userEmojisOption = userEmojisList.filter {
            $0.owner.accountIdentifier == owner.accountIdentifier
        }
        
        var userEmojis: UserEmojis
        if userEmojisOption.count > 0 {
            userEmojis = userEmojisOption[0]
        } else {
            let favs = EmojiView.EmojiModel.getEmojis(type: .favs, owner: owner) ?? []
            let history = EmojiView.EmojiModel.getEmojis(type: .history, owner: owner) ?? []
            userEmojis = .init(owner: owner, favs: favs, history: history)
            userEmojisList.append(userEmojis)
        }
        
        var emojis: [EmojiView.EmojiModel]
        switch kind {
        case .favs:
            emojis = userEmojis.favs
        case .history:
            guard EmojiView.EmojiModel.checkHavingEmojis(type: .history, owner: owner) else { return [] }
            emojis = userEmojis.history
        }
        
        return emojis
    }
    
    func updateUserEmojis(to kind: Kind, owner: SecureUser, new emojis: [EmojiView.EmojiModel]) {
        for i in 0 ..< userEmojisList.count {
            guard userEmojisList[i].owner.accountIdentifier == owner.accountIdentifier else { continue }
            switch kind {
            case .favs:
                userEmojisList[i].favs = emojis
            case .history:
                userEmojisList[i].history = emojis
            }
            return
        }
    }
}

class ReactionGenModel {
    private typealias EmojiModel = EmojiView.EmojiModel
    
    fileprivate class Emojis {
        var currentIndex: Int = 0
        var isLoading: Bool = false
        var preloaded: [EmojiView.EmojiModel] = [] // 非同期で事前に詠み込んでおく
        var categorizedDefault: CategorizedEmojis = .init()
        var categorizedCustom: CategorizedEmojis = .init()
        
        init(from owner: SecureUser?) {
            guard let owner = owner,
                  let handler = EmojiHandler.getHandler(owner: owner) else { return }
            
            categorizedDefault = handler.categorizedDefaultEmojis
            categorizedCustom = handler.categorizedCustomEmojis
        }
    }
    
    // MARK: Private Vars
    
    private lazy var emojis = Emojis(from: self.owner)
    private var maxOnceLoad: Int = 50
    private var defaultPreset = ["👍", "❤️", "😆", "🤔", "😮", "🎉", "💢", "😥", "😇", "🍮", "🤯"]
    private var defaultLoaded = false
    
    // MARK: Life Cycle
    
    private let misskey: MisskeyKit?
    private let owner: SecureUser?
    init(from misskey: MisskeyKit?, owner: SecureUser?) {
        self.misskey = misskey
        self.owner = owner
    }
    
    // MARK: Public Methods
    
    func getFavEmojis() -> [EmojiView.EmojiModel] {
        guard let owner = owner else { return [] }
        guard EmojiModel.checkHavingEmojis(type: .favs, owner: owner) else { // UserDefaultsが存在しないならUserDefaultsセットしておく
            var emojiModels: [EmojiModel] = []
            defaultPreset.forEach { char in
                emojiModels.append(EmojiModel(rawEmoji: char,
                                              isDefault: true,
                                              defaultEmoji: char,
                                              customEmojiUrl: nil))
            }
            
            Repository.shared.updateUserEmojis(to: .favs, owner: owner, new: emojiModels)
            EmojiModel.saveEmojis(with: emojiModels, type: .favs, owner: owner)
            fakeCellPadding(array: &emojiModels, count: defaultPreset.count)
            
            return emojiModels
        }
        
        // UserDefaultsが存在したら...
        var emojiModels = Repository.shared.getUserEmojis(of: .favs, owner: owner)
        
        if emojiModels.count > 0 {
            fakeCellPadding(array: &emojiModels, count: emojiModels.count)
        }
        
        return emojiModels
    }
    
    func getHistoryEmojis() -> [EmojiView.EmojiModel] {
        guard let owner = owner else { return [] }
        var emojiModels = Repository.shared.getUserEmojis(of: .history, owner: owner)
        
        if emojiModels.count > 0 {
            fakeCellPadding(array: &emojiModels, count: emojiModels.count)
        }
        
        return emojiModels
    }
    
    func getEmojiModel() -> Observable<EmojiView.EmojiModel> {
        let dispose = Disposables.create()
        
        return Observable.create { [unowned self] observer in
            // カスタム→デフォルトの順に表示したいので、この順に取り出していく
            for categorized in [self.emojis.categorizedCustom, self.emojis.categorizedDefault] {
                let categories = categorized.map { $0.key }.sorted { $0 < $1 } // 順番を固定するように
                
                categories.forEach { category in // カテゴリーによってセクションを切り分ける(擬似的にヘッダーを作る)
                    guard let emojiModels = categorized[category] else {
                        return
                    }
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
        misskey?.notes.createReaction(noteId: noteId, reaction: reaction) { result, _ in
            completion(result)
        }
    }
    
    func cancelReaction(noteId: String, completion: @escaping (Bool) -> Void) {
        misskey?.notes.deleteReaction(noteId: noteId) { result, _ in
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
        guard let owner = owner else { return }
        
        var history = Repository.shared.getUserEmojis(of: .history, owner: owner)
        if history.count == 0 {
            let newHistory = [emojiModel]
            Repository.shared.updateUserEmojis(to: .history, owner: owner, new: newHistory)
            EmojiModel.saveEmojis(with: newHistory, type: .history, owner: owner)
            return
        }
        
        // 重複する分とpaddingのためのフェイクは除く
        history = history.filter { !$0.isFake && $0.rawEmoji != emojiModel.rawEmoji }
        if history.count >= 7 * 2 { // 2行分だけ表示させる
            history.removeLast()
        }
        
        history.insert(emojiModel, at: 0)
        EmojiModel.saveEmojis(with: history, type: .history, owner: owner)
        Repository.shared.updateUserEmojis(to: .history, owner: owner, new: history)
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
