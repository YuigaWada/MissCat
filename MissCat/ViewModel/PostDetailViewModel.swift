//
//  PostDetailViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/12/01.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import RxSwift

class PostDetailViewModel {
    public let notes: PublishSubject<[NoteCell.Section]> = .init()
    public let forceUpdateIndex: PublishSubject<Int> = .init()
    public var dataSource: NotesDataSource?
    public var cellCount: Int { return cellsModel.count }
    
    private var hasReactionGenCell: Bool = false
    public var cellsModel: [NoteCell.Model] = [] // TODO: エラー再発しないか意識しておく
    
    private let model = PostDetailModel()
    
    //    private lazy var model = PostDetailModel()
    
    // MARK: Life Cycle
    
    init(disposeBag: DisposeBag) {}
    
    public func setItem(_ item: NoteCell.Model) {
        cellsModel.append(item)
        updateNotes(new: cellsModel)
        
        DispatchQueue.global().async {
            self.goBackReplies(item) // リプライ先を遡る
            self.getReplies(item)
        }
    }
    
    // MARK: Setup
    
    // MARK: REST
    
    private func goBackReplies(_ item: NoteCell.Model) {
        var replies = model.goBackReplies(of: item.original?.reply)
        
        replies.reverse()
        cellsModel = replies + cellsModel
        updateNotes(new: cellsModel)
    }
    
    private func getReplies(_ item: NoteCell.Model) {
        guard let noteId = item.noteId else { return }
        model.getReplies(id: noteId) { replies in
            self.cellsModel += replies
            self.updateNotes(new: self.cellsModel)
        }
    }
    
    // MARK: Utilities
    
    private func updateNotes(new: [NoteCell.Model]) {
        updateNotes(new: [NoteCell.Section(items: new)])
    }
    
    private func updateNotes(new: [NoteCell.Section]) {
        notes.onNext(new)
    }
}
