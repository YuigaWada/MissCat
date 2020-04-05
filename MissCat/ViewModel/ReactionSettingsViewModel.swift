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
    
    struct Input {}
    struct Output {
        let favs: PublishSubject<[ReactionGenViewController.EmojisSection]> = .init()
    }
    
    struct State {
        var editting: Bool = false
    }
    
    var output = Output()
    var state = State()
    
    private var disposeBag: DisposeBag
    private var emojis: [EmojiView.EmojiModel] = []
    
    init(_ disposeBag: DisposeBag) {
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
        emojis = EmojiModel.getEmojis(type: .favs) ?? []
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
    
    // MARK: Utilities
    
    private func updateEmojis(_ items: [EmojiView.EmojiModel]) {
        let section = ReactionGenViewController.EmojisSection(items: items)
        updateEmojis(section)
    }
    
    private func updateEmojis(_ section: ReactionGenViewController.EmojisSection) {
        output.favs.onNext([section])
    }
}
