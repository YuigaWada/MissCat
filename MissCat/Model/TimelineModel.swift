//
//  HomeModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/13.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxCocoa
import RxSwift

// MARK: ENUM

public enum TimelineType {
    case Home
    case Local
    case Global
    
    case UserList
    case OneUser
    
    var needsStreaming: Bool {
        return self != .UserList && self != .OneUser
    }
    
    func convert2Channel() -> SentStreamModel.Channel? { // TimelineTypeをMisskeyKit.SentStreamModel.Channelに変換する
        switch self {
        case .Home: return .homeTimeline
        case .Local: return .localTimeline
        case .Global: return .globalTimeline
        default: return nil
        }
    }
}

// MARK: CLASS

class TimelineModel {
    // MARK: I/O
    
    struct LoadOption {
        let type: TimelineType
        let userId: String?
        let untilId: String?
        let includeReplies: Bool?
        let onlyFiles: Bool?
        let listId: String?
        let loadLimit: Int
    }
    
    struct UpdateReaction {
        let targetNoteId: String?
        let rawReaction: String?
        let isMyReaction: Bool
    }
    
    struct Trigger {
        let removeTargetTrigger: PublishSubject<String> // arg: noteId
        let updateReactionTrigger: PublishSubject<UpdateReaction>
    }
    
    public lazy var trigger: Trigger = .init(removeTargetTrigger: self.removeTargetTrigger,
                                             updateReactionTrigger: self.updateReactionTrigger)
    
    public let removeTargetTrigger: PublishSubject<String> = .init() // arg: noteId
    public let updateReactionTrigger: PublishSubject<UpdateReaction> = .init()
    
    public var initialNoteIds: [String] = []
    
    private var type: TimelineType = .Home
    private let handleTargetType: [String] = ["note", "CapturedNoteUpdated"]
    private lazy var streaming = MisskeyKit.Streaming()
    
    // MARK: REST API
    
    public func loadNotes(with option: LoadOption) -> Observable<NoteCell.Model> {
        let dispose = Disposables.create()
        
        return Observable.create { [unowned self] observer in
            
            let handleResult = { (posts: [NoteModel]?, error: MisskeyKitError?) in
                guard let posts = posts, error == nil else {
                    if let error = error { observer.onError(error) }
                    print(error ?? "error is nil")
                    return
                }
                
                posts.forEach { post in
                    // Renote
                    if let renoteId = post.renoteId, let user = post.user, let renote = post.renote {
                        let renoteeCellModel = NoteCell.Model.fakeRenoteecell(renotee: user.name ?? user.username ?? "", baseNoteId: renoteId)
                        observer.onNext(renoteeCellModel)
                        
                        guard let cellModel = renote.getNoteCellModel() else { return }
                        observer.onNext(cellModel)
                    } else { // default note
                        guard let newCellsModel = self.getCellsModel(post) else { return }
                        newCellsModel.forEach { observer.onNext($0) }
                    }
                    
                    if let noteId = post.id {
                        // ここでcaptureしようとしてもwebsocketとの接続が未確定なのでcapture不確実
                        self.initialNoteIds.append(noteId)
                    }
                    
                    // MEMO: セルの描画は必ずメインスレッドで行われるのでさすがにここでやると重い　→ なんかそうでもなさそう
                    //                self.updateNotes(new: self.cellsModel)
                }
                
                observer.onCompleted()
            }
            
            switch option.type {
            case .Home:
                MisskeyKit.notes.getTimeline(limit: option.loadLimit,
                                             untilId: option.untilId ?? "",
                                             completion: handleResult)
                
            case .Local:
                MisskeyKit.notes.getLocalTimeline(limit: option.loadLimit,
                                                  untilId: option.untilId ?? "",
                                                  completion: handleResult)
                
            case .Global:
                MisskeyKit.notes.getGlobalTimeline(limit: option.loadLimit,
                                                   untilId: option.untilId ?? "",
                                                   completion: handleResult)
                
            case .OneUser:
                guard let userId = option.userId else { return dispose }
                MisskeyKit.notes.getUserNotes(includeReplies: option.includeReplies ?? true,
                                              userId: userId,
                                              withFiles: option.onlyFiles ?? false,
                                              limit: option.loadLimit,
                                              untilId: option.untilId ?? "",
                                              completion: handleResult)
                
            case .UserList:
                guard let listId = option.listId else { return dispose }
                MisskeyKit.notes.getUserListTimeline(listId: listId,
                                                     limit: option.loadLimit,
                                                     untilId: option.untilId ?? "",
                                                     completion: handleResult)
            }
            
            return dispose
        }
    }
    
    // MARK: Streaming API
    
    public func connectStream(type: TimelineType) -> Observable<NoteCell.Model> { // streamingのresponseを捌くのはhandleStreamで行う
        let dipose = Disposables.create()
        self.type = type
        
        return Observable.create { [unowned self] observer in
            guard let apiKey = MisskeyKit.auth.getAPIKey(), let channel = type.convert2Channel() else { return dipose }
            
            _ = self.streaming.connect(apiKey: apiKey, channels: [channel]) { (response: Any?, channel: SentStreamModel.Channel?, type: String?, error: MisskeyKitError?) in
                self.handleStream(response: response, channel: channel, typeString: type, error: error, observer: observer)
            }
            
            return dipose
        }
    }
    
    private func handleStream(response: Any?, channel: SentStreamModel.Channel?, typeString: String?, error: MisskeyKitError?, observer: AnyObserver<NoteCell.Model>) {
        let isInitialConnection = self.initialNoteIds.count > 0 // 初期接続かどうか
        if isInitialConnection {
            self.captureNotes(self.initialNoteIds) // websocket接続が確定してからcapture
            self.initialNoteIds = []
        }
        
        if let error = error {
            print(error)
            if error == .CannotConnectStream || error == .NoStreamConnection {
                observer.onError(error)
            }
            return
        }
        
        guard let _ = channel, let typeString = typeString, self.handleTargetType.contains(typeString) else {
            return
        }
        
        if typeString == "CapturedNoteUpdated" {
            guard let updateContents = response as? NoteUpdatedModel, let updateType = updateContents.type, let userId = updateContents.userId else { return }
            
            switch updateType {
            case .reacted:
                userId.isMe { isMyReaction in // 自分のリアクションかどうかチェックする
                    self.updateReaction(targetNoteId: updateContents.targetNoteId,
                                        reaction: updateContents.reaction,
                                        isMyReaction: isMyReaction)
                }
                
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
            observer.onNext(cellModel)
            
            let renoteeCellModel = NoteCell.Model.fakeRenoteecell(renotee: user.name ?? user.username ?? "", baseNoteId: renoteId)
            observer.onNext(renoteeCellModel)
        } else {
            var newCellsModel = self.getCellsModel(post)
            guard newCellsModel != nil else { return }
            
            newCellsModel!.reverse() // reverseしてからinsert
            newCellsModel!.forEach { observer.onNext($0) }
        }
        
        //            self.updateNotes(new: self.cellsModel)
        self.captureNote(noteId: post.id)
    }
    
    // MARK: Capture
    
    private func captureNote(noteId: String?) {
        guard let noteId = noteId else { return }
        captureNotes([noteId])
    }
    
    private func captureNotes(_ noteIds: [String]) {
        noteIds.forEach { id in
            do {
                try streaming.captureNote(noteId: id)
            } catch {
                /* Ignore :P */
            }
        }
    }
    
    // MARK: Remove / Update Cell
    
    private func removeNoteCell(noteId: String) {
        removeTargetTrigger.onNext(noteId)
    }
    
    private func updateReaction(targetNoteId: String?, reaction rawReaction: String?, isMyReaction: Bool) {
        let updateReaction = UpdateReaction(targetNoteId: targetNoteId,
                                            rawReaction: rawReaction,
                                            isMyReaction: isMyReaction)
        
        updateReactionTrigger.onNext(updateReaction)
    }
    
    // MisskeyKitのNoteModelをNoteCell.Modelに変換する
    public func getCellsModel(_ post: NoteModel) -> [NoteCell.Model]? {
        var cellsModel: [NoteCell.Model] = []
        
        if let reply = post.reply { // リプライ対象も表示する
            var replyCellModel = reply.getNoteCellModel()
            
            if replyCellModel != nil {
                replyCellModel!.isReplyTarget = true
                cellsModel.append(replyCellModel!)
            }
        }
        
        if let cellModel = post.getNoteCellModel() {
            cellsModel.append(cellModel)
        }
        
        return cellsModel.count > 0 ? cellsModel : nil
    }
}
