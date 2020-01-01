//
//  NoteCellViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/19.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit
import MisskeyKit
import RxSwift
import RxCocoa
import YanagiText

class NoteCellViewModel: ViewModelType {
    
    //MARK: I/O
    struct Input {
        let cellModel: NoteCell.Model
        let isDetailMode: Bool
        
        //Modelに渡さなければならないので看過
        let noteYanagi: YanagiText
        let nameYanagi: YanagiText
    }
    
    
    struct Output {
        let ago: Driver<String>
        let name: Driver<NSAttributedString?>
        
        let shapedNote: Driver<NSAttributedString?>
        let iconImage: Driver<UIImage>
        
        let defaultConstraintActive: Driver<Bool>
        let isReplyTarget: Driver<Bool>
        
        let backgroundColor: Driver<UIColor>
        
        let displayName: String
        let username: String
    }
    
    struct State {
        
    }
    
    public lazy var output: Output = .init(ago: ago.asDriver(onErrorJustReturn: ""),
                                           name: name.asDriver(onErrorJustReturn: nil),
                                           shapedNote: self.shapedNote.asDriver(onErrorJustReturn: nil),
                                           iconImage: self.iconImage.asDriver(onErrorJustReturn: UIImage()),
                                           defaultConstraintActive: self.defaultConstraintActive.asDriver(onErrorJustReturn: false),
                                           isReplyTarget: self.isReplyTarget.asDriver(onErrorJustReturn: false),
                                           backgroundColor: self.backgroundColor.asDriver(onErrorJustReturn: .white),
                                           displayName: input.cellModel.displayName,
                                           username: input.cellModel.username)
    
    private var input: Input
    private var model = NoteCellModel()
    private var disposeBag: DisposeBag
    
    private var ago: PublishRelay<String> = .init()
    private var name: PublishRelay<NSAttributedString?> = .init()
    
    private var shapedNote: PublishRelay<NSAttributedString?> = .init()
    private var iconImage: PublishRelay<UIImage> = .init()
    private var defaultConstraintActive: PublishRelay<Bool> = .init()
    private var isReplyTarget: PublishRelay<Bool> = .init()
    private var backgroundColor: PublishRelay<UIColor> = .init()
    
    private let replyTargetColor = UIColor(hex: "f0f0f0")
    private let usernameFont = UIFont.systemFont(ofSize: 11.0)
    
    
    private var properBackgroundColor: UIColor {
        return input.cellModel.isReplyTarget ? replyTargetColor : .white
    }
    
    
    //MARK: Life Cycle
    init(with input: Input, and disposeBag: DisposeBag) {
        self.input = input
        self.disposeBag = disposeBag
    }
    
    
    
    public func setCell() {
        let item = input.cellModel
        DispatchQueue.global(qos: .default).async {
            self.defaultConstraintActive.accept(!self.input.isDetailMode)
            self.isReplyTarget.accept(item.isReplyTarget)
            self.backgroundColor.accept(self.properBackgroundColor)
            
            self.ago.accept(item.ago.calculateAgo())
        }
        self.name.accept(self.getDisplayName(item))
        self.shapeNote(identifier: item.identity,
                       note: item.note,
                       noteId: item.noteId,
                       isReply: item.isReply,
                       externalEmojis: item.emojis,
                       isDetailMode: self.input.isDetailMode)
        
        
    }
    
    
    private func shapeNote(identifier: String, note: String, noteId: String? ,isReply: Bool, externalEmojis: [EmojiModel?]?, isDetailMode: Bool) {
        guard let noteId = noteId else { return }
        
        //        DispatchQueue.global(qos: .background).async {
        let cachedNote = Cache.shared.getNote(noteId: noteId) // セルが再利用されるのでキャッシュは中央集権的に
        let hasCachedNote: Bool = cachedNote != nil
        
        let treatedNote = self.model.shapeNote(cache: cachedNote,
                                               identifier: identifier,
                                               note: note,
                                               isReply: isReply,
                                               externalEmojis: externalEmojis,
                                               isDetailMode: isDetailMode,
                                               yanagi: input.noteYanagi)
        
        if !hasCachedNote, let treatedNote = treatedNote {
            Cache.shared.saveNote(noteId: noteId, note: treatedNote, attachments: input.noteYanagi.getAttachments()) // CHACHE!
        }
        
        self.shapedNote.accept(treatedNote)
        //        }
    }
    
    private func getDisplayName(_ item: NoteCell.Model)-> NSAttributedString? {
        let name = item.displayName
        let username = " @" + item.username
        
        let shapedName = name.mfmTransform(yanagi: self.input.nameYanagi, lineHeight: self.input.nameYanagi.frame.height * 0.9) ?? .init()
        
        return shapedName + username.getAttributedString(font: self.usernameFont,
                                                         color: .darkGray)
    }
    
    public func setImage(username: String, imageRawUrl: String?)-> String? {
        if let image = Cache.shared.getIcon(username: username) {
            iconImage.accept(image)
        }
        else if let imageRawUrl = imageRawUrl, let imageUrl = URL(string: imageRawUrl) {
            
            imageUrl.toUIImage{ [weak self] image in
                guard let self = self, let image = image else { return }
                Cache.shared.saveIcon(username: username, image: image) // CHACHE!
                self.iconImage.accept(image)
            }
            
            return imageRawUrl
        }
        
        return nil
    }
    
    
    public func registerReaction(noteId: String, reaction: String) {
        model.registerReaction(noteId: noteId, reaction: reaction)
    }
    
    public func cancelReaction(noteId: String){
        model.cancelReaction(noteId: noteId)
    }
}
