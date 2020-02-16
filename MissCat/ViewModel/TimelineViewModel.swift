//
//  HomeViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/12.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxCocoa
import RxSwift

private typealias Model = TimelineModel

class TimelineViewModel: ViewModelType {
    // MARK: I/O
    
    struct Input {
        let dataSource: NotesDataSource
        
        let type: TimelineType
        let includeReplies: Bool?
        let onlyFiles: Bool?
        let userId: String?
        let listId: String?
        let loadLimit: Int
    }
    
    struct Output {
        let notes: PublishSubject<[NoteCell.Section]> = .init()
        let forceUpdateIndex: PublishSubject<Int> = .init()
        
        let finishedLoading: PublishRelay<Bool> = .init()
        let connectedStream: PublishRelay<Bool> = .init()
    }
    
    class State {
        var cellCount: Int
        init(cellCount: Int) {
            self.cellCount = cellCount
        }
    }
    
    private let input: Input
    public lazy var output: Output = .init()
    public var state: State {
        return .init(cellCount: { cellsModel.count }())
    }
    
    // MARK: PublishSubject
    
    private var hasReactionGenCell: Bool = false
    public var cellsModel: [NoteCell.Model] = [] // TODO: エラー再発しないか意識しておく
    private var initialNoteIds: [String] = [] // WebSocketの接続が確立してからcaptureするためのキャッシュ
    
    private lazy var model = TimelineModel()
    private var dataSource: NotesDataSource?
    private var disposeBag: DisposeBag
    
    // MARK: Life Cycle
    
    public init(with input: Input, and disposeBag: DisposeBag) {
        self.input = input
        self.disposeBag = disposeBag
    }
    
    public func setupInitialCell() {
        setSkeltonCell()
        loadNotes {
            DispatchQueue.main.async {
                self.output.finishedLoading.accept(true)
                
                self.updateNotes(new: self.cellsModel)
                self.removeSkeltonCell()
                
                guard self.input.type.needsStreaming else { return }
                self.connectStream()
            }
        }
    }
    
    // MARK: Streaming
    
    private func connectStream() {
        model.connectStream(type: input.type)
            .subscribe(onNext: { cellModel in
                self.output.connectedStream.accept(true)
                
                self.cellsModel.insert(cellModel, at: 0)
                self.updateNotes(new: self.cellsModel)
                
            }, onError: { _ in
                self.output.connectedStream.accept(false)
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
    
    // MARK: Remove / Update Cell
    
    private func removeNoteCell(noteId: String) {
        let targetCell = cellsModel.filter { $0.noteId == noteId }
        if targetCell.count > 0, let targetIndex = self.cellsModel.firstIndex(of: targetCell[0]) {
            cellsModel.remove(at: targetIndex)
            updateNotes(new: cellsModel)
        }
    }
    
    private func updateReaction(targetNoteId: String?, reaction rawReaction: String?, isMyReaction: Bool) {
        guard let targetNoteId = targetNoteId, let rawReaction = rawReaction else { return }
        
        let targetCell = cellsModel.filter { $0.noteId == targetNoteId }
        if targetCell.count > 0, let targetIndex = self.cellsModel.firstIndex(of: targetCell[0]) {
            // Change Count Label
            let existReactionCount = cellsModel[targetIndex].reactions.filter {
                guard let reaction = $0 else { return false }
                return reaction.name == rawReaction
            }
            
            let hasThisReaction = existReactionCount.count > 0
            if hasThisReaction {
                cellsModel[targetIndex].reactions = cellsModel[targetIndex].reactions.map { counter in
                    guard let counter = counter else { return nil }
                    
                    var newReactionCounter = counter
                    if counter.name == rawReaction, let count = counter.count {
                        newReactionCounter.count = count.increment()
                    }
                    
                    return newReactionCounter
                }
            } else {
                let newReaction = ReactionCount(name: rawReaction, count: "1")
                cellsModel[targetIndex].reactions.append(newReaction)
            }
            
            // My reaction...?
            if isMyReaction {
                cellsModel[targetIndex].myReaction = rawReaction
            }
            
            updateNotes(new: cellsModel)
            updateNotesForcibly(index: targetIndex)
        }
    }
    
    // MARK: REST
    
    // 古い投稿から順にfetchしてくる
    public func loadUntilNotes(completion: (() -> Void)? = nil) {
        guard let untilId = self.cellsModel[self.cellsModel.count - 1].noteId else { return }
        
        loadNotes(untilId: untilId) {
            self.updateNotes(new: self.cellsModel)
            if let completion = completion { completion() }
        }
    }
    
    // 投稿をfetchしてくる
    public func loadNotes(untilId: String? = nil, completion: (() -> Void)? = nil) {
        let option = Model.LoadOption(type: input.type,
                                      userId: input.userId,
                                      untilId: untilId,
                                      includeReplies: input.includeReplies,
                                      onlyFiles: input.onlyFiles,
                                      listId: input.listId,
                                      loadLimit: input.loadLimit)
        
        model.loadNotes(with: option).subscribe(onNext: { cellModel in
            self.cellsModel.append(cellModel)
        }, onCompleted: {
            self.initialNoteIds = self.model.initialNoteIds
            if let completion = completion { completion() }
        }, onDisposed: nil)
            .disposed(by: disposeBag)
    }
    
    func getCell(cell itemCell: NoteCell, item: NoteCell.Model) -> NoteCell {
        return itemCell.shapeCell(item: item)
    }
    
    // MARK: Utilities
    
    // dataSourceからnoteを探してtargetのindexの下にreactiongencell入れる
    public func tappedReaction(noteId: String, hasMarked: Bool) {
        guard cellsModel.filter({ $0.baseNoteId == noteId }).count == 0 else {
            // 複数個reactiongencellを挿入させない
            return
        }
        
        if hasMarked {
            return
        }
    }
    
    private func setSkeltonCell() {
        for _ in 0 ..< 10 {
            let skeltonCellModel = NoteCell.Model.fakeSkeltonCell()
            cellsModel.append(skeltonCellModel)
        }
        
        updateNotes(new: cellsModel)
    }
    
    private func removeSkeltonCell() {
        let removed = cellsModel.suffix(cellsModel.count - 10)
        cellsModel = Array(removed)
        
        updateNotes(new: cellsModel)
    }
    
    // MARK: RxSwift
    
    private func updateNotes(new: [NoteCell.Model]) {
        updateNotes(new: [NoteCell.Section(items: new)])
    }
    
    private func updateNotes(new: [NoteCell.Section]) {
        output.notes.onNext(new)
    }
    
    private func updateNotesForcibly(index: Int) {
        output.forceUpdateIndex.onNext(index)
    }
}
