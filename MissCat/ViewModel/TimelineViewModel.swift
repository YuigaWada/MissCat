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
        private let loadLimit: Int
        var cellCount: Int
        var renoteeCellCount: Int
        var isLoading: Bool
        
        var cellCompleted: Bool { // 準備した分のセルがすべて表示されたかどうか
            return (cellCount - renoteeCellCount) % loadLimit == 0
        }
        
        init(cellCount: Int, renoteeCellCount: Int, isLoading: Bool, loadLimit: Int) {
            self.cellCount = cellCount
            self.renoteeCellCount = renoteeCellCount
            self.isLoading = isLoading
            self.loadLimit = loadLimit
        }
    }
    
    private let input: Input
    public let output: Output = .init()
    
    private var _isLoading: Bool = false
    public var state: State {
        return .init(cellCount: { cellsModel.count }(),
                     renoteeCellCount: { cellsModel.filter { $0.isRenoteeCell }.count }(),
                     isLoading: _isLoading,
                     loadLimit: input.loadLimit)
    }
    
    // MARK: PublishSubject
    
    private var hasReactionGenCell: Bool = false
    public var cellsModel: [NoteCell.Model] = [] // TODO: エラー再発しないか意識しておく
    private var initialNoteIds: [String] = [] // WebSocketの接続が確立してからcaptureするためのキャッシュ
    private var hasSkeltonCell: Bool = false
    private let usernameFont = UIFont.systemFont(ofSize: 11.0)
    
    private lazy var model = TimelineModel()
    private var dataSource: NotesDataSource?
    private var disposeBag: DisposeBag
    
    // MARK: Life Cycle
    
    public init(with input: Input, and disposeBag: DisposeBag) {
        self.input = input
        self.disposeBag = disposeBag
    }
    
    public func setupInitialCell() {
        // タイムラインをロードする
        loadNotes().subscribe(onError: { error in
            print(error)
        }, onCompleted: {
            DispatchQueue.main.async {
                self.output.finishedLoading.accept(true)
                
                self.updateNotes(new: self.cellsModel)
                self.removeSkeltonCell()
                
                guard self.input.type.needsStreaming else { return }
                self.connectStream()
            }
        }, onDisposed: nil).disposed(by: disposeBag)
    }
    
    public func setSkeltonCell() {
        guard !hasSkeltonCell else { return }
        
        for _ in 0 ..< 5 {
            let skeltonCellModel = NoteCell.Model.fakeSkeltonCell()
            cellsModel.append(skeltonCellModel)
        }
        
        updateNotes(new: cellsModel)
        hasSkeltonCell = true
    }
    
    private func removeSkeltonCell() {
        guard hasSkeltonCell else { return }
        let removed = cellsModel.suffix(cellsModel.count - 5)
        cellsModel = Array(removed)
        
        updateNotes(new: cellsModel)
    }
    
    // MARK: Streaming
    
    private func connectStream() {
        model.connectStream(type: input.type)
            .subscribe(onNext: { cellModel in
                self.output.connectedStream.accept(true)
                
                self.shapeModel(cellModel)
                
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
        if targetCell.count > 0, let targetIndex = cellsModel.firstIndex(of: targetCell[0]) {
            cellsModel.remove(at: targetIndex)
            updateNotes(new: cellsModel)
        }
    }
    
    private func updateReaction(targetNoteId: String?, reaction rawReaction: String?, isMyReaction: Bool) {
        guard let targetNoteId = targetNoteId, let rawReaction = rawReaction else { return }
        
        let targetCell = cellsModel.filter { $0.noteId == targetNoteId }
        if targetCell.count > 0, let targetIndex = cellsModel.firstIndex(of: targetCell[0]) {
            // Change Count Label
            let existReactionCount = cellsModel[targetIndex].reactions.filter { $0.name == rawReaction }
            
            let hasThisReaction = existReactionCount.count > 0
            if hasThisReaction {
                cellsModel[targetIndex].reactions = cellsModel[targetIndex].reactions.map { counter in
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
            
            cellsModel[targetIndex].shapedReactions = cellsModel[targetIndex].getReactions()
            
            updateNotes(new: cellsModel)
            updateNotesForcibly(index: targetIndex)
        }
    }
    
    // MARK: REST
    
    // 古い投稿から順にfetchしてくる
    public func loadUntilNotes() -> Observable<NoteCell.Model> {
        guard let untilId = cellsModel[cellsModel.count - 1].noteId else {
            return Observable.create { _ in
                Disposables.create()
            }
        }
        
        return loadNotes(untilId: untilId).do(onCompleted: {
            self.updateNotes(new: self.cellsModel)
        })
    }
    
    // 投稿をfetchしてくる
    public func loadNotes(untilId: String? = nil) -> Observable<NoteCell.Model> {
        let option = Model.LoadOption(type: input.type,
                                      userId: input.userId,
                                      untilId: untilId,
                                      includeReplies: input.includeReplies,
                                      onlyFiles: input.onlyFiles,
                                      listId: input.listId,
                                      loadLimit: input.loadLimit,
                                      isReload: false,
                                      lastNoteId: nil)
        _isLoading = true
        
        return model.loadNotes(with: option).do(onNext: { cellModel in
            self.shapeModel(cellModel)
            self.cellsModel.append(cellModel)
        }, onCompleted: {
            self.initialNoteIds = self.model.initialNoteIds
            self._isLoading = false
        })
    }
    
    public func getCell(cell itemCell: NoteCell, item: NoteCell.Model) -> NoteCell {
        return itemCell.transform(with: .init(item: item))
    }
    
    public func vote(choice: Int, to noteId: String) {
        model.vote(choice: choice, to: noteId) // API叩く
        
        cellsModel = cellsModel.map { // セルのモデルを変更する
            guard $0.noteId == noteId,
                let poll = $0.poll,
                let choices = poll.choices,
                let votes = choices[choice]?.votes else { return $0 }
            
            let cellModel = $0
            cellModel.poll?.choices?[choice]?.votes = votes + 1
            cellModel.poll?.choices?[choice]?.isVoted = true
            return cellModel
        }
    }
    
    public func renote(noteId: String) {
        model.renote(noteId: noteId)
    }
    
    public func reloadNotes() {
        guard let lastNoteId = cellsModel[0].noteId else { return }
        
        let option = Model.LoadOption(type: input.type,
                                      userId: input.userId,
                                      untilId: nil,
                                      includeReplies: input.includeReplies,
                                      onlyFiles: input.onlyFiles,
                                      listId: input.listId,
                                      loadLimit: 10,
                                      isReload: true,
                                      lastNoteId: lastNoteId)
        
        model.loadNotes(with: option).subscribe(onNext: { cellModel in
            self.shapeModel(cellModel)
            self.cellsModel.insert(cellModel, at: 0)
        }, onCompleted: {
            self.updateNotes(new: self.cellsModel)
        }).disposed(by: disposeBag)
    }
    
    // MARK: Utilities
    
    private func shapeModel(_ cellModel: NoteCell.Model) {
        cellModel.shapedNote = shapeNote(cellModel)
        cellModel.shapedDisplayName = shapeDisplayName(cellModel)
        
        if let commentRNTarget = cellModel.commentRNTarget {
            commentRNTarget.shapedNote = shapeNote(commentRNTarget)
            commentRNTarget.shapedDisplayName = shapeDisplayName(commentRNTarget)
        }
    }
    
    private func shapeNote(_ cellModel: NoteCell.Model) -> MFMString {
        let replyHeader: NSMutableAttributedString = cellModel.isReply ? .getReplyMark() : .init() // リプライの場合は先頭にreplyマークつける
        let mfmString = cellModel.note.mfmTransform(font: UIFont(name: "Helvetica", size: 11.0) ?? .systemFont(ofSize: 11.0),
                                                    externalEmojis: cellModel.emojis,
                                                    lineHeight: 30)
        
        return MFMString(mfmEngine: mfmString.mfmEngine, attributed: replyHeader + (mfmString.attributed ?? .init()))
    }
    
    private func shapeDisplayName(_ cellModel: NoteCell.Model) -> MFMString {
        let mfmString = cellModel.displayName.mfmTransform(font: UIFont(name: "Helvetica", size: 10.0) ?? .systemFont(ofSize: 10.0),
                                                           externalEmojis: cellModel.emojis,
                                                           lineHeight: 25)
        
        return MFMString(mfmEngine: mfmString.mfmEngine,
                         attributed: (mfmString.attributed ?? .init()) + " @\(cellModel.username)".getAttributedString(font: usernameFont,
                                                                                                                       color: .darkGray))
    }
    
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
