//
//  HomeViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/12.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import RxSwift
import MisskeyKit


class TimelineViewModel
{
    public let notes: PublishSubject<[NoteCell.Section]> = .init()
    public let forceUpdateIndex: PublishSubject<Int> = .init()
    public var dataSource: NotesDataSource?
    public var cellCount: Int { return cellsModel.count }
    
    
    private var hasReactionGenCell: Bool = false
    public var cellsModel: [NoteCell.Model] = [] //TODO: エラー再発しないか意識しておく
    private var initialNoteIds: [String] = [] // WebSocketの接続が確立してからcaptureするためのキャッシュ
    
    private let handleTargetType: [String] = ["note", "CapturedNoteUpdated"]
    private lazy var model = TimelineModel()
    private lazy var streaming = MisskeyKit.Streaming()
    
    private var type: TimelineType = .Home
    private var userId: String? = nil
    private var listId: String? = nil
    private var includeReplies: Bool? = nil
    private var onlyFiles: Bool? = nil
    
    
    //MARK: Life Cycle
    init(type: TimelineType, includeReplies: Bool? = nil, onlyFiles: Bool? = nil, userId: String? = nil, listId: String? = nil, disposeBag: DisposeBag) {
        
        self.type = type
        self.userId = userId
        self.listId = listId
        
        self.includeReplies = includeReplies
        self.onlyFiles = onlyFiles
        
        self.loadNotes(){
            self.updateNotes(new: self.cellsModel)
            
            if type.needsStreaming {
                DispatchQueue.main.async { self.connectStream() }
            }
            
        }
    }
    
    
    
    
    //MARK: Streaming
    private func connectStream() { //streamingのresponseを捌くのはhandleStreamで行う
        guard let apiKey = MisskeyKit.auth.getAPIKey(), let channel = self.type.convert2Channel() else { return }
        
        let _ = streaming.connect(apiKey: apiKey, channels: [channel], response: self.handleStream)
    }
    
    private func handleStream(response: Any?, channel: SentStreamModel.Channel?, type: String?, error: MisskeyKitError?) {
        let isInitialConnection = initialNoteIds.count > 0 //初期接続かどうか
        if isInitialConnection {
            self.captureNotes(initialNoteIds) //websocket接続が確定してからcapture
            initialNoteIds = []
        }
        
        
        if let error = error {
            print(error)
            if error == .CannotConnectStream || error == .NoStreamConnection { self.connectStream() }
            return
        }
        guard let _ = channel, let type = type, self.handleTargetType.contains(type) else {
            return }
        
        if type == "CapturedNoteUpdated" {
            guard let updateContents = response as? NoteUpdatedModel, let updateType = updateContents.type, let userId = updateContents.userId else { return }
            
            switch updateType {
            case .reacted:
                userId.isMe { isMyReaction in //自分のリアクションかどうかチェックする
                    self.updateReaction(targetNoteId: updateContents.targetNoteId,
                                        reaction: updateContents.reaction,
                                        isMyReaction: isMyReaction) }
                
                break
                
            case .pollVoted:
                break
            case .deleted:
                guard let targetNoteId = updateContents.targetNoteId else { return }
                self.removeNoteCell(noteId: targetNoteId)
            }
            
        }
        
        guard let post = response as? NoteModel else { return }
        
        if let renoteId = post.renoteId, let user = post.user, let renote = post.renote {
            guard let cellModel = renote.getNoteCellModel() else { return }
            self.cellsModel.insert(cellModel, at:0)
            
            let renoteeCellModel = NoteCell.Model.fakeRenoteecell(renotee: user.name ?? user.username ?? "", baseNoteId: renoteId)
            self.cellsModel.insert(renoteeCellModel, at:0)
        }
        else {
            var newCellsModel = self.model.getCellsModel(post)
            guard newCellsModel != nil else { return }
            
            newCellsModel!.reverse()//reverseしてからinsert
            newCellsModel!.forEach{ self.cellsModel.insert($0, at:0) }
        }
        
        self.updateNotes(new: self.cellsModel)
        self.captureNote(noteId: post.id)
    }
    
    
    //Capture
    private func captureNote(noteId: String?) {
        guard let noteId = noteId else { return }
        self.captureNotes([noteId])
    }
    
    private func captureNotes(_ noteIds: [String]) {
        noteIds.forEach { id in
            do {
                try streaming.captureNote(noteId: id)
            }
            catch {
                /* Ignore :P */
            }
        }
    }
    
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
    
    
    
    //MARK: Communicate with View
    
    //古い投稿から順にfetchしてくる
    public func loadUntilNotes(completion: (()->())? = nil) {
        guard let untilId = self.cellsModel[self.cellsModel.count - 1].noteId else { return }
        
        self.loadNotes(untilId: untilId) {
            self.updateNotes(new: self.cellsModel)
            if let completion = completion { completion() }
        }
    }
    
    //投稿をfetchしてくる
    public func loadNotes(untilId: String? = nil, completion: (()->())? = nil) {
        let handleResult = { (posts: [NoteModel]?, error: MisskeyKitError?) in
            guard let posts = posts, error == nil else { /* Error */ print(error ?? "error is nil"); return }
            
            posts.forEach{ post in
                print("post!\(posts.count)")
                dump(post)
                
                if let renoteId = post.renoteId, let user = post.user, let renote = post.renote {
                    let renoteeCellModel = NoteCell.Model.fakeRenoteecell(renotee: user.name ?? user.username ?? "", baseNoteId: renoteId)
                    self.cellsModel.append(renoteeCellModel)
                    
                    guard let cellModel = renote.getNoteCellModel() else { return }
                    self.cellsModel.append(cellModel)
                }
                else {
                    guard let newCellsModel = self.model.getCellsModel(post) else { return }
                    newCellsModel.forEach{ self.cellsModel.append($0) }
                }
                
                if let noteId = post.id {
                    //ここでcaptureしようとしてもwebsocketとの接続が未確定なのでcapture不確実
                    self.initialNoteIds.append(noteId)
                }
                
                //MEMO: セルの描画は必ずメインスレッドで行われるのでさすがにここでやると重い　→ なんかそうでもなさそう
                self.updateNotes(new: self.cellsModel)
            }
            
            if let completion = completion { completion() }
        }
        
        switch type {
        case .Home: MisskeyKit.notes.getTimeline(limit: 40, untilId: untilId ?? "", completion: handleResult)
            
        case .Local: MisskeyKit.notes.getLocalTimeline(limit: 40, untilId: untilId ?? "", completion: handleResult)
            
        case .Global: MisskeyKit.notes.getGlobalTimeline(limit: 40, untilId: untilId ?? "", completion: handleResult)
            
        case .OneUser:
            guard let userId = userId else { return }
            MisskeyKit.notes.getUserNotes(includeReplies: includeReplies ?? true,
                                          userId: userId,
                                          withFiles: onlyFiles ?? false,
                                          limit: 40,
                                          untilId: untilId ?? "",
                                          completion: handleResult)
            
        case .UserList:
            guard let listId = listId else { return }
            MisskeyKit.notes.getUserListTimeline(listId: listId, limit: 40, untilId: untilId ?? "", completion: handleResult)
        }
        
    }
    
    
    func getCell(cell itemCell: NoteCell, item: NoteCell.Model)-> NoteCell {
        return itemCell.shapeCell(item: item)
    }
    
    //HyperLinkを用途ごとに捌く
    public func analyzeHyperLink(_ text: String)-> (linkType: String, value: String) {
        let magicHeaders = ["http://tapevents.misscat/": "User", "http://hashtags.misscat/": "Hashtag"]
        var result = (linkType: "URL", value: text)
        
        magicHeaders.keys.forEach { magicHeader in
            guard let type = magicHeaders[magicHeader], text.count > magicHeader.count else { return }
            
            let header = String(text.prefix(magicHeader.count))
            let value = text.suffix(text.count - magicHeader.count)
            
            //ヘッダーが一致するものをresultに返す
            guard header == magicHeader else { return }
            result = (linkType: type, value: String(value))
        }
        
        // if header != magicHeader
        return result
    }
    
    //dataSourceからnoteを探してtargetのindexの下にreactiongencell入れる
    public func tappedReaction(noteId: String, hasMarked: Bool) {
        
        guard self.cellsModel.filter({ $0.baseNoteId == noteId }).count == 0 else {
            //複数個reactiongencellを挿入させない
            self.resetReactionGenCell(baseNoteId: noteId, baseEqual: true)
            return
        }
        
        if hasMarked {
            return
        }
        
//        guard let dataSource = self.dataSource else { return }
        //        let cells = dataSource.sectionModels[0].items
        
        //        let noteCell = cells.filter { $0.noteId == noteId }
        
        //Viewが実際にReactionGenCellを挿入するので、model上でReactionGenCellと区別する
        //        if noteCell.count > 0, let cellIndex = cells.firstIndex(of: noteCell[0]) {
        //            let reactionGenCell = NoteCell.Model.fakeReactionGenCell(baseNoteId: noteId)
        //
        //            cellsModel.insert(reactionGenCell, at:cellIndex + 1)
        //            self.updateNotes(new: self.cellsModel)
        //            self.hasReactionGenCell = true
        //        }
    }
    
    // ReactionGenCellをtableViewから取り除く
    // allClear: 除去条件を制定するかどうか、すなわち全ReactionGenCellを消すかどうか
    // baseEqual: 除去条件がbaseNoteIdの一致であるかどうか
    public func resetReactionGenCell(allClear: Bool = false, baseNoteId: String = "", baseEqual: Bool = false) {
        guard self.hasReactionGenCell else { return }
        
        
        //reactionGenCellのみ削除
        if !allClear {
            self.cellsModel = self.cellsModel.filter { cell in
                let isResetTarget = (cell.baseNoteId != baseNoteId) == !baseEqual //NOT ( baseNoteId is equal (XOR) baseEqual )
                return !(cell.isReactionGenCell && isResetTarget)
            }
        }
        else {
            self.cellsModel = self.cellsModel.filter { !$0.isReactionGenCell }
        }
        
        
        self.hasReactionGenCell = false
        self.updateNotes(new: self.cellsModel)
    }
    
    public func isReactionGenCell(index: Int)-> Bool {
        guard self.cellsModel.count >= index else { return false }
        
        return self.cellsModel[index].isReactionGenCell
    }
    
    
    //MARK: RxSwift
    private func updateNotes(new: [NoteCell.Model]) {
        self.updateNotes(new: [NoteCell.Section(items: new)])
    }
    
    private func updateNotes(new: [NoteCell.Section]) {
        //        DispatchQueue.main.async { self.notes.onNext(new) }
        self.notes.onNext(new)
    }
    
    private func updateNotesForcibly(index: Int) {
        self.forceUpdateIndex.onNext(index)
    }
}

