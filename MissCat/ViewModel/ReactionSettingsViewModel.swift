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
    
    struct State {}
    
    var output = Output()
    private var disposeBag: DisposeBag
    private var emojis: [EmojiView.EmojiModel] = []
    
    init(_ disposeBag: DisposeBag) {
        self.disposeBag = disposeBag
    }
    
    func setEmojiModel() {
        emojis = EmojiModel.getEmojis(type: .favs) ?? []
        updateEmojis(emojis)
    }
    
    func moveItem(moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let tempNumber = emojis.remove(at: sourceIndexPath.item)
        emojis.insert(tempNumber, at: destinationIndexPath.item)
        updateEmojis(emojis)
    }
    
    func addEmoji(_ emojiModel: EmojiView.EmojiModel) {
        emojis.append(emojiModel)
        updateEmojis(emojis)
    }
    
    private func updateEmojis(_ items: [EmojiView.EmojiModel]) {
        let section = ReactionGenViewController.EmojisSection(items: items)
        updateEmojis(section)
    }
    
    private func updateEmojis(_ section: ReactionGenViewController.EmojisSection) {
        output.favs.onNext([section])
    }
}
