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

public class NoteCellViewModel {
    
    private var model = NoteCellModel()
    
    public var shapedNote: PublishSubject<NSAttributedString?> = .init()
    public var iconImage: PublishSubject<UIImage> = .init()
    
    public func shapeNote(identifier: String, note: String, noteId: String? ,isReply: Bool, externalEmojis: [EmojiModel?]?, isDetailMode: Bool) {
        guard let noteId = noteId else { return }
        
//        DispatchQueue.global(qos: .background).async {
            let cachedNote = Cache.shared.getNote(noteId: noteId) // セルが再利用されるのでキャッシュは中央集権的に
            let hasCachedNote: Bool = cachedNote != nil
             
            let treatedNote = self.model.shapeNote(cache: cachedNote,
                                              identifier: identifier,
                                              note: note,
                                              isReply: isReply,
                                              externalEmojis: externalEmojis,
                                              isDetailMode: isDetailMode)
            
            if !hasCachedNote, let treatedNote = treatedNote {
                Cache.shared.saveNote(noteId: noteId, note: treatedNote) // CHACHE!
            }
            
            self.shapedNote.onNext(treatedNote)
//        }
    }
    
    
    public func setImage(username: String, imageRawUrl: String?)-> String? {
        if let image = Cache.shared.getIcon(username: username) {
            iconImage.onNext(image)
        }
        else if let imageRawUrl = imageRawUrl, let imageUrl = URL(string: imageRawUrl) {
            
            imageUrl.toUIImage{ [weak self] image in
                guard let self = self, let image = image else { return }
                Cache.shared.saveIcon(username: username, image: image) // CHACHE!
                self.iconImage.onNext(image)
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
