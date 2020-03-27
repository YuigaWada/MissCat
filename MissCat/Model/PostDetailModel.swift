//
//  PostDetailModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/27.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit

public class PostDetailModel {
    private var backReplies: [NoteCell.Model] = []
    private var replies: [NoteCell.Model] = []
    
    /// リプライを遡る
    /// - Parameter note: モデル
    public func goBackReplies(id: String, completion: @escaping ([NoteCell.Model]) -> Void) {
        MisskeyKit.notes.showNote(noteId: id) { note, error in
            guard error == nil,
                let note = note,
                let shaped = note.getNoteCellModel() else { completion(self.backReplies); return }
            
            shaped.isReplyTarget = true
            MFMEngine.shapeModel(shaped)
            self.backReplies.append(shaped)
            
            if let replyId = note.replyId {
                self.goBackReplies(id: replyId, completion: completion)
            } else {
                completion(self.backReplies)
            }
        }
    }
    
    /// リプライを探す
    /// - Parameter id: noteId
    public func getReplies(id: String, completion: @escaping ([NoteCell.Model]) -> Void) {
        MisskeyKit.notes.getChildren(noteId: id) { notes, error in
            guard let notes = notes, error == nil else { return }
            DispatchQueue.global().async {
                self.replies = self.convertReplies(notes)
                completion(self.replies)
            }
        }
    }
    
    /// NoteModelをNoteCell.Modelへ
    /// - Parameter notes: [NoteModel]
    private func convertReplies(_ notes: [NoteModel]) -> [NoteCell.Model] {
        return notes.map {
            guard let cellModel = $0.getNoteCellModel() else { return nil }
            MFMEngine.shapeModel(cellModel)
            return cellModel
        }.compactMap { $0 }
    }
}
