//
//  ReactionSettingsViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/05.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxCocoa
import RxDataSources
import RxSwift

private typealias EmojiModel = EmojiView.EmojiModel
class ReactionSettingsViewModel: ViewModelType {
    // MARK: I/O
    
    struct Input {
        let owner: SecureUser
    }
    
    struct Output {
        let favs: PublishSubject<[ReactionGenViewController.EmojisSection]> = .init()
    }
    
    struct State {
        var editting: Bool = false
        var saved: Bool = true
    }
    
    private let input: Input
    var output = Output()
    var state = State()
    
    private var disposeBag: DisposeBag
    private var emojis: [EmojiView.EmojiModel] = []
    private var defaultPresets = ["👍", "❤️", "😆", "🤔", "😮", "🎉", "💢", "😥", "😇", "🍮", "🤯"]
    
    init(with input: Input, and disposeBag: DisposeBag) {
        self.input = input
        self.disposeBag = disposeBag
    }
    
    // MARK: Publics
    
    /// 編集中かどうかstateを変更
    /// - Parameter editState: true: 変更中
    func changeEditState(_ editState: Bool) {
        state.editting = editState
    }
    
    /// UserDefaultsからお気に入り絵文字を取得する
    func setEmojiModel() {
        emojis = getEmojis()
        updateEmojis(emojis)
    }
    
    /// 指でセルを移動させた後、実際に絵文字モデルも変更させる
    /// - Parameters:
    ///   - sourceIndexPath: sourceIndexPath
    ///   - destinationIndexPath: destinationIndexPath
    func moveItem(moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let tempNumber = emojis.remove(at: sourceIndexPath.item)
        emojis.insert(tempNumber, at: destinationIndexPath.item)
        updateEmojis(emojis)
    }
    
    /// 絵文字をcollectionViewの最末端へ追加する
    /// - Parameter emojiModel: EmojiView.EmojiModel
    func addEmoji(_ emojiModel: EmojiView.EmojiModel) {
        emojis.append(emojiModel)
        updateEmojis(emojis)
    }
    
    /// セルを削除する
    /// - Parameter index: Int
    func removeCell(_ index: Int) {
        guard index >= 0, index < emojis.count, state.editting else { return }
        
        emojis.remove(at: index)
        updateEmojis(emojis)
    }
    
    /// お気に入り絵文字を保存する
    func save() {
        EmojiView.EmojiModel.saveEmojis(with: emojis, type: .favs, owner: input.owner)
        EmojiRepository.shared.updateUserEmojis(to: .favs, owner: input.owner, new: emojis)
        state.saved = true
    }
    
    // MARK: Utilities
    
    private func updateEmojis(_ items: [EmojiView.EmojiModel]) {
        let section = ReactionGenViewController.EmojisSection(items: items)
        updateEmojis(section)
    }
    
    private func updateEmojis(_ section: ReactionGenViewController.EmojisSection) {
        output.favs.onNext([section])
        state.saved = false
    }
    
    private func getEmojis() -> [EmojiModel] {
        guard let emojis = EmojiModel.getEmojis(type: .favs, owner: input.owner), emojis.count > 0 else { return getDefaultsPreset() }
        return emojis
    }
    
    private func getDefaultsPreset() -> [EmojiModel] {
        return defaultPresets.map { EmojiModel(rawEmoji: $0,
                                               isDefault: true,
                                               defaultEmoji: $0,
                                               customEmojiUrl: nil) }
    }
}
