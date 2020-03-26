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
        let lockTableScroll: PublishRelay<Bool> = .init()
        
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
        var reloadTopModelId: String? // untilLoadした分のセルのうち、最上端にある投稿のid
        
        var cellCompleted: Bool { // 準備した分のセルがすべて表示されたかどうか
            return (cellCount - renoteeCellCount) % loadLimit == 0
        }
        
        init(cellCount: Int, renoteeCellCount: Int, isLoading: Bool, loadLimit: Int, reloadTopModelId: String? = nil) {
            self.cellCount = cellCount
            self.renoteeCellCount = renoteeCellCount
            self.isLoading = isLoading
            self.loadLimit = loadLimit
            self.reloadTopModelId = reloadTopModelId
        }
    }
    
    private let input: Input
    public let output: Output = .init()
    
    private var reloadTopModelId: String?
    private var _isLoading: Bool = false
    public var state: State {
        return .init(cellCount: { cellsModel.count }(),
                     renoteeCellCount: { cellsModel.filter { $0.isRenoteeCell }.count }(),
                     isLoading: _isLoading,
                     loadLimit: input.loadLimit,
                     reloadTopModelId: reloadTopModelId)
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
    
    private var initialNoteCount: Int = 0
    
    // MARK: Life Cycle
    
    public init(with input: Input, and disposeBag: DisposeBag) {
        self.input = input
        self.disposeBag = disposeBag
    }
    
    public func setupInitialCell() {
        // タイムラインをロードする
        loadNotes().subscribe(onError: { error in
            if let error = error as? TimelineModel.NotesLoadingError, error == .NotesEmpty, self.input.type == .Home {
                self.initialPost()
            }
            
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
    
    private func initialPost() {
        guard initialNoteCount < 2 else { return }
        MisskeyKit.notes.createNote(text: "MissCatからアカウントを作成しました。") { note, error in
            guard note != nil, error == nil else { // 失敗した場合は何回か再帰
                self.initialNoteCount += 1
                self.initialPost()
                return
            }
            DispatchQueue.main.async {
                self.initialNoteCount = 0
                self.initialFollow() // 次にユーザーをフォローしておく
            }
        }
    }
    
    private func initialFollow() {
        guard initialNoteCount < 2 else { return }
        MisskeyKit.users.follow(userId: "7ze0f2goa7") { user, error in
            guard user != nil, error == nil else { // 失敗した場合は何回か再帰
                self.initialNoteCount += 1
                self.initialFollow()
                return
            }
            DispatchQueue.main.async {
                self.setupInitialCell() // 成功したらまたタイムラインのロードを試みる
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
                self.reloadNotes {
                    self.connectStream() // リロード完了後にstreamingへ接続
                }
            })
            .disposed(by: disposeBag)
        
        model.trigger.removeTargetTrigger.subscribe(onNext: { noteId in
            self.removeNoteCell(noteId: noteId)
        })
            .disposed(by: disposeBag)
        
        model.trigger.updateReactionTrigger.subscribe(onNext: { info in
            self.updateReaction(targetNoteId: info.targetNoteId,
                                reaction: info.rawReaction,
                                isMyReaction: info.isMyReaction,
                                plus: info.plus)
        })
            .disposed(by: disposeBag)
    }
    
    // MARK: Remove / Update Cell
    
    private func removeNoteCell(noteId: String) {
        findNoteIndex(noteId: noteId).forEach { targetIndex in
            cellsModel.remove(at: targetIndex)
            updateNotes(new: cellsModel)
            updateNotesForcibly(index: targetIndex)
        }
    }
    
    public func updateReaction(targetNoteId: String?, reaction rawReaction: String?, isMyReaction: Bool, plus: Bool, needReloading: Bool = true) {
        guard let targetNoteId = targetNoteId, let rawReaction = rawReaction else { return }
        
        DispatchQueue.global().async {
            self.findNoteIndex(noteId: targetNoteId).forEach { targetIndex in
                
                let existReactionCount = self.cellsModel[targetIndex].reactions.filter { $0.name == rawReaction }
                let hasThisReaction = existReactionCount.count > 0
                
                if hasThisReaction { // 別のユーザーがリアクションしていた場合
                    self.cellsModel[targetIndex].reactions = self.cellsModel[targetIndex].reactions.map { counter in
                        var newReactionCounter = counter
                        if counter.name == rawReaction, let count = counter.count {
                            let mustRemove = count == "1" && !plus
                            
                            guard !mustRemove else { return nil } // 1→0なのでmodel自体を削除
                            newReactionCounter.count = plus ? count.increment() : count.decrement()
                        }
                        
                        return newReactionCounter
                    }.compactMap { $0 }
                } else {
                    let newReaction = ReactionCount(name: rawReaction, count: "1")
                    self.cellsModel[targetIndex].reactions.append(newReaction)
                }
                
                // My reaction...?
                if isMyReaction {
                    self.cellsModel[targetIndex].myReaction = rawReaction
                }
                
                self.cellsModel[targetIndex].shapedReactions = self.cellsModel[targetIndex].getReactions()
                
                if needReloading {
                    self.updateNotes(new: self.cellsModel)
                    self.updateNotesForcibly(index: targetIndex)
                }
            }
        }
    }
    
    /// 指定されたnoteIdを持つ投稿のindexを返します
    /// - Parameter noteId: noteId
    private func findNoteIndex(noteId: String) -> [Int] {
        return cellsModel.filter { $0.noteId == noteId }
            .map { cellsModel.firstIndex(of: $0) }
            .compactMap { $0 }
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
            self.output.lockTableScroll.accept(false) // スクロールのロックを解除
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
            self.cellsModel.append(cellModel)
            if untilId != nil, self.reloadTopModelId == nil { // reloadTopModelIdを記憶
                self.reloadTopModelId = cellModel.identity
            }
        }, onCompleted: {
            self.initialNoteIds = self.model.initialNoteIds
            self._isLoading = false
        })
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
    
    public func reloadNotes(_ completion: @escaping () -> Void) {
        guard let lastNoteId = getLastNoteId() else { return }
        
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
            self.cellsModel.insert(cellModel, at: 0)
        }, onCompleted: {
            self.updateNotes(new: self.cellsModel)
            completion()
        }).disposed(by: disposeBag)
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
    
    private func getLastNoteId() -> String? {
        guard cellsModel.count > 0 else { return nil }
        
        let lastNote = cellsModel[0]
        if lastNote.isRenoteeCell { // RNの場合はRenoteeCellのModelが送られてくるので次のモデルを参照する
            guard cellsModel.count > 1 else { return nil }
            return cellsModel[1].noteId
        }
        
        return lastNote.noteId
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
