//
//  NotificationCellViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/24.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxCocoa
import RxSwift
import UIKit

class NotificationCellViewModel: ViewModelType {
    // MARK: I/O
    
    struct Input {
        let item: NotificationCell.Model
    }
    
    struct Output {
        // Meta
        let ago: PublishRelay<String> = .init()
        let name: PublishRelay<MFMString> = .init()
        let iconImage: PublishRelay<UIImage> = .init()
        
        // Note
        let note: PublishRelay<MFMString> = .init()
        
        // Color
        let mainColor: PublishRelay<UIColor> = .init()
        let backgroundColor: PublishRelay<UIColor> = .init()
        let selectedBackgroundColor: PublishRelay<UIColor> = .init()
        let textColor: PublishRelay<UIColor> = .init()
        
        // Response
        let type: PublishRelay<ActionType> = .init()
        let typeString: PublishRelay<String> = .init()
        let typeIconString: PublishRelay<String> = .init()
        let typeIconColor: PublishRelay<UIColor> = .init()
        
        let emoji: PublishRelay<EmojiView.EmojiModel> = .init()
        
        // Flag
        let needEmoji: PublishRelay<Bool> = .init()
    }
    
    struct State {}
    
    private var input: Input
    var output: Output = .init()
    
    private lazy var reactionIconColor = UIColor(red: 231 / 255, green: 76 / 255, blue: 60 / 255, alpha: 1)
    private lazy var renoteIconColor = UIColor(red: 46 / 255, green: 204 / 255, blue: 113 / 255, alpha: 1)
    private var mainColor: UIColor = {
        guard let mainColorHex = Theme.shared.currentModel?.mainColorHex else { return .systemBlue }
        return UIColor(hex: mainColorHex)
    }()
    
    private var imageSessionTasks: [URLSessionDataTask] = []
    
    private var disposeBag: DisposeBag
    private var model = NotificationCellModel()
    
    // MARK: LifeCycle
    
    init(with input: Input, and disposeBag: DisposeBag) {
        self.disposeBag = disposeBag
        self.input = input
    }
    
    func prepareForReuse() {
        imageSessionTasks.forEach { task in
            task.cancel()
        }
        imageSessionTasks.removeAll()
    }
    
    // MARK: Set
    
    func setCell() {
        let item = input.item
        if !item.isMock, item.fromUser?.username == nil {
            return
        }
        
        setImage(item)
        setGeneral(item)
        
        setNote(item)
        setResponse(item)
        setColor()
    }
    
    private func setImage(_ item: NotificationCell.Model) {
        let username = item.fromUser?.username ?? ""
        let host = item.fromUser?.host ?? ""
        if let image = Cache.shared.getIcon(username: "\(username)@\(host)") {
            output.iconImage.accept(image)
        } else if let iconImageUrl = item.fromUser?.avatarUrl, let iconUrl = URL(string: iconImageUrl) {
            let task = iconUrl.toUIImage { [weak self] image in
                guard let self = self, let image = image else { return }
                
                DispatchQueue.main.async {
                    Cache.shared.saveIcon(username: username, image: image) // CHACHE!
                    self.output.iconImage.accept(image)
                }
            }
            
            if let task = task {
                imageSessionTasks.append(task)
            }
        }
    }
    
    private func setGeneral(_ item: NotificationCell.Model) {
        if let shapedDisplayName = item.shapedDisplayName {
            output.name.accept(shapedDisplayName)
        }
        output.ago.accept(item.ago.calculateAgo())
    }
    
    private func setNote(_ item: NotificationCell.Model) {
        guard let myNote = item.myNote,
            let shapedNote = myNote.shapedNote else { return }
        
        // file
        let fileCount = myNote.noteEntity.files.count
        if fileCount > 0, let attributedMyNote = shapedNote.attributed {
            let mfmString = MFMString(mfmEngine: shapedNote.mfmEngine,
                                      attributed: attributedMyNote + NSAttributedString(string: "\n> \(fileCount)つのファイル "))
            
            output.note.accept(mfmString)
        } else {
            output.note.accept(shapedNote)
        }
    }
    
    private func setResponse(_ item: NotificationCell.Model) {
        let type = item.type
        output.type.accept(type)
        
        // renote
        if type == .renote {
            output.typeIconString.accept("retweet")
            output.typeString.accept("Renote")
            output.needEmoji.accept(false)
            output.typeIconColor.accept(renoteIconColor)
        }
        
        // reaction
        else if let reaction = item.reaction {
            guard let owner = input.item.owner,
                let handler = EmojiHandler.getHandler(owner: owner) else { return }
            output.typeIconString.accept("heart")
            output.typeString.accept("Reaction")
            output.needEmoji.accept(true)
            output.typeIconColor.accept(reactionIconColor)
            output.emoji.accept(handler.convert2EmojiModel(raw: reaction, external: item.emojis))
        }
        
        // follow
        else if type == .follow {
            output.typeIconString.accept("user-friends")
            output.typeString.accept("Follow")
            output.typeIconColor.accept(mainColor)
            output.needEmoji.accept(false)
        }
    }
    
    private func setColor() {
        output.mainColor.accept(mainColor)
        if let currentModel = Theme.shared.currentModel {
            if currentModel.colorMode == .dark {
                output.selectedBackgroundColor.accept(currentModel.colorPattern.ui.sub2)
            }
        }
    }
}
