//
//  HomeViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/12.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import RxCocoa
import RxSwift
import MisskeyKit

fileprivate typealias Model = TimelineModel

class TimelineViewModel: ViewModelType
{
    
    //MARK: I/O
    struct Input {
        let dataSource: NotesDataSource
        
        let type: TimelineType
        let includeReplies: Bool?
        let onlyFiles: Bool?
        let userId: String?
        let listId: String?
    }
    
    struct Output {
        let notes: Driver<[NoteCell.Section]>
        let forceUpdateIndex: Driver<Int>
        
        let finishedLoading: Driver<Bool>
        let connectedStream: Driver<Bool>
    }
    
    class State {
        var cellCount: Int
        init(cellCount: Int) {
            self.cellCount = cellCount
        }
    }
    
    private let input: Input
    public lazy var output: Output = .init(notes: self.notes.asDriver(onErrorJustReturn: []),
                                           forceUpdateIndex: self.forceUpdateIndex.asDriver(onErrorJustReturn: 0),
                                           finishedLoading: self.finishedLoading.asDriver(onErrorJustReturn: false),
                                           connectedStream: self.connectedStream.asDriver(onErrorJustReturn: false))
    public var state: State {
        return .init(cellCount: { return cellsModel.count }())
    }
    
    
    
    //MARK: PublishSubject
    private let notes: PublishSubject<[NoteCell.Section]> = .init()
    private let forceUpdateIndex: PublishSubject<Int> = .init()
    
    private let finishedLoading: PublishRelay<Bool> = .init()
    private let connectedStream: PublishRelay<Bool> = .init()

    
    private var hasReactionGenCell: Bool = false
    public var cellsModel: [NoteCell.Model] = [] //TODO: エラー再発しないか意識しておく
    private var initialNoteIds: [String] = [] // WebSocketの接続が確立してからcaptureするためのキャッシュ
    
    
    private lazy var model = TimelineModel()
    private var dataSource: NotesDataSource?
    private var disposeBag: DisposeBag
    
    
    
    
    //MARK: Life Cycle
    public init(with input: Input, and disposeBag: DisposeBag) {
        self.input = input
        self.disposeBag = disposeBag
    }
    
    public func setupInitialCell() {
        self.setSkeltonCell()
        self.loadNotes(){
            DispatchQueue.main.async {
                self.finishedLoading.accept(true)
                
                self.updateNotes(new: self.cellsModel)
                self.removeSkeltonCell()
                
                guard self.input.type.needsStreaming else { return }
                self.connectStream()
                
            }
        }
    }
    
    
    //MARK: Streaming
    private func connectStream() {
        model.connectStream(type: input.type)
            .subscribe(onNext: { cellModel in
                self.connectedStream.accept(true)
                
                self.cellsModel.insert(cellModel, at: 0)
                self.updateNotes(new: self.cellsModel)
                
            }, onError: { error in
                self.connectedStream.accept(false)
                self.connectStream()
            })
            .disposed(by: disposeBag)
        
        model.trigger.removeTargetTrigger.subscribe(onNext: { noteId in
            self.removeNoteCell(noteId: noteId)
        })
        .disposed(by: disposeBag)
        
        model.trigger.updateReactionTrigger.subscribe(onNext: { info in
            self.updateReaction(targetNoteId: info.targetNoteId, reaction: info.rawReaction, isMyReaction: info.isMyReaction)
        })
        .disposed(by: disposeBag)
        
        
    }
    
    
    //MARK: Remove / Update Cell
    private func removeNoteCell(noteId: String) {
        let targetCell = self.cellsModel.filter { $0.noteId == noteId }
        if targetCell.count > 0, let targetIndex = self.cellsModel.firstIndex(of: targetCell[0]) {
            self.cellsModel.remove(at: targetIndex)
            self.updateNotes(new: self.cellsModel)
        }
    }
    
    private func updateReaction(targetNoteId: String?, reaction rawReaction: String?, isMyReaction: Bool) {
        guard let targetNoteId = targetNoteId, let rawReaction = rawReaction else { return }
        
        let targetCell = self.cellsModel.filter { $0.noteId == targetNoteId }
        if targetCell.count > 0, let targetIndex = self.cellsModel.firstIndex(of: targetCell[0]) {
            
            // Change Count Label
            let existReactionCount = self.cellsModel[targetIndex].reactions.filter {
                guard let reaction = $0 else { return false }
                return reaction.name == rawReaction
            }
            
            let hasThisReaction = existReactionCount.count > 0
            if hasThisReaction {
                self.cellsModel[targetIndex].reactions = self.cellsModel[targetIndex].reactions.map { counter in
                    guard let counter = counter else { return nil }
                    
                    var newReactionCounter = counter
                    if counter.name == rawReaction, let count = counter.count {
                        newReactionCounter.count = count.increment()
                    }
                    
                    return newReactionCounter
                }
                
            }
            else {
                let newReaction = ReactionCount(name: rawReaction, count: "1")
                self.cellsModel[targetIndex].reactions.append(newReaction)
            }
            
            // My reaction...?
            if isMyReaction {
                self.cellsModel[targetIndex].myReaction = rawReaction
            }
            
            self.updateNotes(new: self.cellsModel)
            self.updateNotesForcibly(index: targetIndex)
        }
    }
    
    //MARK: REST
    
    //古い投稿から順にfetchしてくる
    public func loadUntilNotes(completion: (()->())? = nil) {
        guard let untilId = self.cellsModel[self.cellsModel.count - 1].noteId else { return }
        
//        self.loadNotes(untilId: untilId) {
//            self.updateNotes(new: self.cellsModel)
//            if let completion = completion { completion() }
//        }
    }
    
    //投稿をfetchしてくる
    public func loadNotes(untilId: String? = nil, completion: (()->())? = nil) {
        let option = Model.LoadOption(type: input.type,
                                      userId: input.userId,
                                      untilId: untilId,
                                      includeReplies: input.includeReplies,
                                      onlyFiles: input.onlyFiles,
                                      listId: input.listId)
        
        model.loadNotes(with: option) {
            
            self.initialNoteIds = self.model.initialNoteIds
            if let completion = completion { completion() }
            
        }
        .subscribe(onNext: { cellModel in
            
            self.cellsModel.append(cellModel)
//            self.updateNotes(new: self.cellsModel)
            
        }, onCompleted: nil, onDisposed: nil)
            .disposed(by: disposeBag)
    }
    
    
    func getCell(cell itemCell: NoteCell, item: NoteCell.Model)-> NoteCell {
        return itemCell.shapeCell(item: item)
    }
    
    
    //MARK: Utilities
    //dataSourceからnoteを探してtargetのindexの下にreactiongencell入れる
    public func tappedReaction(noteId: String, hasMarked: Bool) {
        
        guard self.cellsModel.filter({ $0.baseNoteId == noteId }).count == 0 else {
            //複数個reactiongencellを挿入させない
            return
        }
        
        if hasMarked {
            return
        }
    }
    
    private func setSkeltonCell() {
        for _ in 0..<10 {
            let skeltonCellModel = NoteCell.Model.fakeSkeltonCell()
            self.cellsModel.append(skeltonCellModel)
        }
        
        self.updateNotes(new: self.cellsModel)
    }
    
    private func removeSkeltonCell() {
        let removed = self.cellsModel.suffix(self.cellsModel.count - 10)
        self.cellsModel = Array(removed)
        
        self.updateNotes(new: self.cellsModel)
    }
    
    //MARK: RxSwift
    private func updateNotes(new: [NoteCell.Model]) {
        self.updateNotes(new: [NoteCell.Section(items: new)])
    }
    
    private func updateNotes(new: [NoteCell.Section]) {
        self.notes.onNext(new)
    }
    
    private func updateNotesForcibly(index: Int) {
        self.forceUpdateIndex.onNext(index)
    }
}

