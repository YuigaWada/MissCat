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
        let owner: SecureUser
        let dataSource: NotesDataSource
        let type: TimelineType
        let includeReplies: Bool?
        let onlyFiles: Bool?
        let userId: String?
        let listId: String?
        let query: String?
        let lockScroll: Bool
        let loadLimit: Int
    }
    
    struct Output {
        let lockTableScroll: PublishRelay<Bool> = .init()
        
        let notes: PublishSubject<[NoteCell.Section]> = .init()
        let forceUpdateIndex: PublishSubject<Int> = .init()
        
        let finishedLoading: PublishRelay<Bool> = .init()
        let connectedStream: PublishRelay<Bool> = .init()
        
        let reserveLockTrigger: PublishRelay<Void> = .init()
    }
    
    class State {
        private let loadLimit: Int
        var cellCount: Int
        var renoteeCellCount: Int
        var isLoading: Bool
        
        var hasSkeltonCell: Bool
        var owner: SecureUser
        
        var cellCompleted: Bool { // 準備した分のセルがすべて表示されたかどうか
            return (cellCount - renoteeCellCount) % loadLimit == 0
        }
        
        var hasAccounts: Bool {
            return Cache.UserDefaults.shared.getUsers().count > 0
        }
        
        init(cellCount: Int, renoteeCellCount: Int, isLoading: Bool, loadLimit: Int, hasSkeltonCell: Bool, owner: SecureUser) {
            self.cellCount = cellCount
            self.renoteeCellCount = renoteeCellCount
            self.isLoading = isLoading
            self.loadLimit = loadLimit
            self.hasSkeltonCell = hasSkeltonCell
            self.owner = owner
        }
    }
    
    private let input: Input
    let output: Output = .init()
    
    private var _isLoading: Bool = false
    var state: State {
        return .init(cellCount: { cellsModel.count }(),
                     renoteeCellCount: { cellsModel.filter { $0.isRenoteeCell }.count }(),
                     isLoading: _isLoading,
                     loadLimit: input.loadLimit,
                     hasSkeltonCell: hasSkeltonCell,
                     owner: input.owner)
    }
    
    // MARK: PublishSubject
    
    private var hasReactionGenCell: Bool = false
    var cellsModel: [NoteCell.Model] = [] // TODO: エラー再発しないか意識しておく
    private var initialNoteIds: [String] = [] // WebSocketの接続が確立してからcaptureするためのキャッシュ
    private var hasSkeltonCell: Bool = false
    private let usernameFont = UIFont.systemFont(ofSize: 11.0)
    
    private lazy var misskey = MisskeyKit(from: input.owner)
    private lazy var model = TimelineModel(from: misskey)
    
    private var owner: SecureUser?
    private var dataSource: NotesDataSource?
    private var disposeBag: DisposeBag
    
    private var initialNoteCount: Int = 0
    
    // MARK: Life Cycle
    
    init(with input: Input, and disposeBag: DisposeBag) {
        self.input = input
        self.disposeBag = disposeBag
        owner = input.owner
        
        binding()
    }
    
    private func binding() {
        model.trigger.removeTargetTrigger.subscribe(onNext: { noteId in
            self.removeNoteCell(noteId: noteId)
        }).disposed(by: disposeBag)
        
        model.trigger.updateReactionTrigger.subscribe(onNext: { info in
            self.updateReaction(targetNoteId: info.targetNoteId,
                                reaction: info.rawReaction,
                                isMyReaction: info.isMyReaction,
                                plus: info.plus,
                                external: info.externalEmoji)
        }).disposed(by: disposeBag)
    }
    
    func setupInitialCell() {
        // タイムラインをロードする
        loadNotes().subscribe(onError: { error in
            if let error = error as? TimelineModel.NotesLoadingError, error == .NotesEmpty, self.input.type == .Home {
                self.initialFollow()
            }
            
            print(error)
        }, onCompleted: {
            self.output.lockTableScroll.accept(self.input.lockScroll) // ロックの初期状態を決める
            DispatchQueue.main.async {
                self.output.finishedLoading.accept(true)
                
                self.updateNotes(new: self.cellsModel)
                self.removeSkeltonCell()
                
                guard self.input.type.needsStreaming else { return }
                self.connectStream()
            }
        }, onDisposed: nil).disposed(by: disposeBag)
    }
    
    func setSkeltonCell() {
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
    
    private func initialFollow() {
        guard initialNoteCount < 2 else { return }
        misskey?.users.follow(userId: "7ze0f2goa7") { _, error in
            guard error == nil else { // 失敗した場合は何回か再帰
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
    
    private func connectStream(isReconnection: Bool = false) {
        guard let owner = owner else { return }
        model.connectStream(owner: owner, type: input.type, isReconnection: isReconnection)
            .subscribe(onNext: { cellModel in
                self.output.connectedStream.accept(true)
                
                self.cellsModel.insert(cellModel, at: 0)
                self.updateNotes(new: self.cellsModel)
            }, onError: { _ in
                self.output.connectedStream.accept(false)
                self.reloadNotes {
                    self.connectStream(isReconnection: true) // リロード完了後にstreamingへ接続
                }
            }).disposed(by: disposeBag)
    }
    
    // MARK: Remove / Update Cell
    
    private func removeNoteCell(noteId: String) {
        findNoteIndex(noteId: noteId).forEach { targetIndex in
            cellsModel.remove(at: targetIndex)
            updateNotes(new: cellsModel)
            updateNotesForcibly(index: targetIndex)
        }
    }
    
    func updateReaction(targetNoteId: String?, reaction rawReaction: String?, isMyReaction: Bool, plus: Bool, external externalEmoji: EmojiModel?, needReloading: Bool = true) {
        guard let targetNoteId = targetNoteId, let rawReaction = rawReaction else { return }
        
        findNoteIndex(noteId: targetNoteId).forEach { targetIndex in
            
            if let externalEmoji = externalEmoji {
                self.cellsModel[targetIndex].emojis?.append(externalEmoji) // 絵文字を追加しておく
            }
            
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
            
            self.cellsModel[targetIndex].shapedReactions = self.cellsModel[targetIndex].getReactions(with: self.cellsModel[targetIndex].emojis)
            
            if needReloading {
                self.updateNotes(new: self.cellsModel)
                self.updateNotesForcibly(index: targetIndex)
            }
        }
    }
    
    /// 特定ユーザーの投稿をすべてTLから削除
    /// - Parameter userId: userId
    private func removeUser(of userId: String) {
        cellsModel.filter { $0.userId == userId }
            .map { cellsModel.firstIndex(of: $0) }
            .compactMap { $0 }
            .forEach { targetIndex in
                cellsModel.remove(at: targetIndex)
                updateNotes(new: cellsModel)
                updateNotesForcibly(index: targetIndex)
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
    func loadUntilNotes() -> Observable<NoteCell.Model> {
        guard let untilId = cellsModel[cellsModel.count - 1].noteId else {
            return Observable.create { _ in
                Disposables.create()
            }
        }
        
        return loadNotes(untilId: untilId).do(onCompleted: {
            if self.input.lockScroll {
                self.output.lockTableScroll.accept(false) // スクロールのロックを解除
                self.output.reserveLockTrigger.accept(())
            }
            self.updateNotes(new: self.cellsModel)
        })
    }
    
    // 投稿をfetchしてくる
    func loadNotes(untilId: String? = nil) -> Observable<NoteCell.Model> {
        let option = Model.LoadOption(type: input.type,
                                      userId: input.userId,
                                      untilId: untilId,
                                      includeReplies: input.includeReplies,
                                      onlyFiles: input.onlyFiles,
                                      listId: input.listId,
                                      loadLimit: input.loadLimit,
                                      query: input.query,
                                      isReload: false,
                                      lastNoteId: nil)
        _isLoading = true
        
        return model.loadNotes(with: option, from: input.owner).do(onNext: { cellModel in
            self.cellsModel.append(cellModel)
        }, onCompleted: {
            self.initialNoteIds = self.model.initialNoteIds
            self._isLoading = false
        })
    }
    
    func vote(choice: Int, to noteId: String) {
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
    
    func renote(noteId: String) {
        model.renote(noteId: noteId)
    }
    
    func report(message: String, userId: String) {
        removeUser(of: userId)
        model.report(message: message, userId: userId)
    }
    
    func block(userId: String) {
        removeUser(of: userId)
        model.block(userId)
    }
    
    func deleteMyNote(noteId: String) {
        removeNoteCell(noteId: noteId)
        model.deleteMyNote(noteId)
    }
    
    func reloadNotes(_ completion: @escaping () -> Void) {
        guard let lastNoteId = getLastNoteId() else { return }
        
        let option = Model.LoadOption(type: input.type,
                                      userId: input.userId,
                                      untilId: nil,
                                      includeReplies: input.includeReplies,
                                      onlyFiles: input.onlyFiles,
                                      listId: input.listId,
                                      loadLimit: 10,
                                      query: input.query,
                                      isReload: true,
                                      lastNoteId: lastNoteId)
        
        model.loadNotes(with: option, from: input.owner).subscribe(onNext: { cellModel in
            self.cellsModel.insert(cellModel, at: 0)
        }, onCompleted: {
            self.updateNotes(new: self.cellsModel)
            completion()
        }).disposed(by: disposeBag)
    }
    
    // dataSourceからnoteを探してtargetのindexの下にreactiongencell入れる
    func tappedReaction(noteId: String, hasMarked: Bool) {
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
        if lastNote.isRenoteeCell || lastNote.isReplyTarget || lastNote.isPromotionCell { // RN/リプライ/RRの場合はRenoteeCellのModelが送られてくるので次のモデルを参照する
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
