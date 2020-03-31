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

enum TimelineType {
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
        
        let isReload: Bool
        let lastNoteId: String?
    }
    
    struct UpdateReaction {
        let targetNoteId: String?
        let rawReaction: String?
        let isMyReaction: Bool
        let plus: Bool
    }
    
    struct Trigger {
        let removeTargetTrigger: PublishSubject<String> // arg: noteId
        let updateReactionTrigger: PublishSubject<UpdateReaction>
    }
    
    enum NotesLoadingError: Error {
        case NotesEmpty
    }
    
    lazy var trigger: Trigger = .init(removeTargetTrigger: self.removeTargetTrigger,
                                      updateReactionTrigger: self.updateReactionTrigger)
    
    let removeTargetTrigger: PublishSubject<String> = .init() // arg: noteId
    let updateReactionTrigger: PublishSubject<UpdateReaction> = .init()
    
    var initialNoteIds: [String] = []
    private var capturedNoteIds: [String] = []
    
    private var type: TimelineType = .Home
    private let handleTargetType: [String] = ["note", "CapturedNoteUpdated"]
    private lazy var streaming = MisskeyKit.Streaming()
    
    // MARK: Shape NoteModel
    
    private func transformNote(with observer: AnyObserver<NoteCell.Model>, post: NoteModel, reverse: Bool) {
        let noteType = checkNoteType(post)
        if noteType == .Renote {
            guard let renoteId = post.renoteId,
                let user = post.user,
                let renote = post.renote,
                let renoteModel = renote.getNoteCellModel(withRN: checkNoteType(renote) == .CommentRenote) else { return }
            
            let renoteeModel = NoteCell.Model.fakeRenoteecell(renotee: user.name ?? user.username ?? "",
                                                              renoteeUserName: user.username ?? "",
                                                              baseNoteId: renoteId)
            
            var cellModels = [renoteeModel, renoteModel]
            if reverse { cellModels.reverse() }
            
            for cellModel in cellModels {
                MFMEngine.shapeModel(cellModel)
                observer.onNext(cellModel)
            }
            
        } else { // just a note or a note with commentRN
            var newCellsModel = getCellsModel(post, withRN: noteType == .CommentRenote)
            guard newCellsModel != nil else { return }
            
            if reverse { newCellsModel!.reverse() } // reverseしてからinsert (streamingの場合)
            newCellsModel!.forEach {
                MFMEngine.shapeModel($0)
                observer.onNext($0)
            }
        }
    }
    
    // MARK: REST API
    
    func loadNotes(with option: LoadOption) -> Observable<NoteCell.Model> {
        let dispose = Disposables.create()
        let isReload = option.isReload && (option.lastNoteId != nil)
        
        return Observable.create { [unowned self] observer in
            
            let handleResult = { (posts: [NoteModel]?, error: MisskeyKitError?) in
                guard let posts = posts, error == nil else {
                    if let error = error { observer.onError(error) }
                    print(error ?? "error is nil")
                    return
                }
                
                if posts.count == 0 { // 新規登録された場合はpostsが空集合
                    observer.onError(NotesLoadingError.NotesEmpty)
                }
                
                DispatchQueue.global().async {
                    if isReload {
                        // timelineにすでに表示してある投稿を取得した場合、ロードを終了する
                        var newPosts: [NoteModel] = []
                        for index in 0 ..< posts.count {
                            let post = posts[index]
                            if post._featuredId_ == nil { // ハイライトの投稿は無視する
                                // 表示済みの投稿に当たったらbreak
                                guard option.lastNoteId != post.id, option.lastNoteId != post.renoteId else { break }
                                newPosts.append(post)
                            }
                        }
                        
                        newPosts.reverse() // 逆順に読み込む
                        newPosts.forEach { post in
                            self.transformNote(with: observer, post: post, reverse: true)
                            if let noteId = post.id { self.initialNoteIds.append(noteId) }
                        }
                        
                        observer.onCompleted()
                        return
                    }
                    
                    // if !isReload...
                    
                    posts.forEach { post in
                        guard post._featuredId_ == nil else { return } // ハイライトの投稿は無視する
                        
                        self.transformNote(with: observer, post: post, reverse: false)
                        if let noteId = post.id {
                            self.initialNoteIds.append(noteId) // ここでcaptureしようとしてもwebsocketとの接続が未確定なのでcapture不確実
                        }
                    }
                    
                    observer.onCompleted()
                }
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
    
    func report(message: String, userId: String) {
        MisskeyKit.users.reportAsAbuse(userId: userId, comment: message) { _, _ in
        }
    }
    
    func block(_ userId: String) {
        MisskeyKit.users.block(userId: userId) { _, _ in
        }
    }
    
    func deleteMyNote(_ noteId: String) {
        MisskeyKit.notes.deletePost(noteId: noteId) { _, _ in
        }
    }
    
    // MARK: Streaming API
    
    func connectStream(type: TimelineType, isReconnection reconnect: Bool = false) -> Observable<NoteCell.Model> { // streamingのresponseを捌くのはhandleStreamで行う
        let dipose = Disposables.create()
        var isReconnection = reconnect
        self.type = type
        
        return Observable.create { [unowned self] observer in
            guard let apiKey = MisskeyKit.auth.getAPIKey(), let channel = type.convert2Channel() else { return dipose }
            
            _ = self.streaming.connect(apiKey: apiKey, channels: [channel]) { (response: Any?, channel: SentStreamModel.Channel?, type: String?, error: MisskeyKitError?) in
                self.captureNote(&isReconnection)
                self.handleStream(response: response,
                                  channel: channel,
                                  typeString: type,
                                  error: error,
                                  observer: observer)
            }
            
            return dipose
        }
    }
    
    private func handleStream(response: Any?, channel: SentStreamModel.Channel?, typeString: String?, error: MisskeyKitError?, observer: AnyObserver<NoteCell.Model>) {
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
                    guard !isMyReaction else { return } // 自分のリアクションはcaptureしない
                    self.updateReaction(targetNoteId: updateContents.targetNoteId,
                                        reaction: updateContents.reaction,
                                        isMyReaction: isMyReaction,
                                        plus: true)
                }
                
            case .pollVoted:
                break
            case .deleted:
                guard let targetNoteId = updateContents.targetNoteId else { return }
                self.updateReaction(targetNoteId: updateContents.targetNoteId,
                                    reaction: updateContents.reaction,
                                    isMyReaction: false,
                                    plus: false)
            }
        }
        
        guard let post = response as? NoteModel else { return }
        
        transformNote(with: observer, post: post, reverse: true)
        self.captureNote(noteId: post.id)
    }
    
    // MARK: Capture
    
    private func captureNote(_ isReconnection: inout Bool) {
        // 再接続の場合
        if isReconnection {
            captureNotes(capturedNoteIds)
            isReconnection = false
        }
        
        let isInitialConnection = initialNoteIds.count > 0 // 初期接続かどうか
        if isInitialConnection {
            captureNotes(initialNoteIds)
            initialNoteIds = []
        }
    }
    
    private func captureNote(noteId: String?) {
        guard let noteId = noteId else { return }
        captureNotes([noteId])
    }
    
    private func captureNotes(_ noteIds: [String]) {
        capturedNoteIds += noteIds // streamingが切れた時のために記憶
        noteIds.forEach { id in
            do {
                try streaming.captureNote(noteId: id)
            } catch {
                /* Ignore :P */
            }
        }
    }
    
    // MARK: Update Cell
    
    private func updateReaction(targetNoteId: String?, reaction rawReaction: String?, isMyReaction: Bool, plus: Bool) {
        let updateReaction = UpdateReaction(targetNoteId: targetNoteId,
                                            rawReaction: rawReaction,
                                            isMyReaction: isMyReaction,
                                            plus: plus)
        
        updateReactionTrigger.onNext(updateReaction)
    }
    
    // MisskeyKitのNoteModelをNoteCell.Modelに変換する
    func getCellsModel(_ post: NoteModel, withRN: Bool = false) -> [NoteCell.Model]? {
        var cellsModel: [NoteCell.Model] = []
        
        if let reply = post.reply { // リプライ対象も表示する
            let replyWithRN = checkNoteType(reply) == .CommentRenote
            var replyCellModel = reply.getNoteCellModel(withRN: replyWithRN)
            
            if replyCellModel != nil {
                replyCellModel!.isReplyTarget = true
                cellsModel.append(replyCellModel!)
            }
        }
        
        if let cellModel = post.getNoteCellModel(withRN: withRN) {
            cellsModel.append(cellModel)
        }
        
        return cellsModel.count > 0 ? cellsModel : nil
    }
    
    func vote(choice: Int, to noteId: String) {
        MisskeyKit.notes.vote(noteId: noteId, choice: choice, result: { _, _ in
            //            print(error)
        })
    }
    
    func renote(noteId: String) {
        MisskeyKit.notes.renote(renoteId: noteId) { _, _ in
            //            print(error)
        }
    }
}

// MARK; Utilities
extension TimelineModel {
    fileprivate enum NoteType {
        case Renote
        case CommentRenote
        case Note
    }
    
    /// NoteModelが RNなのか、引用RNなのか、ただの投稿なのか判別する
    /// - Parameter post: NoteModel
    private func checkNoteType(_ post: NoteModel) -> NoteType {
        let isRenote = post.renoteId != nil && post.user != nil && post.renote != nil
        let isCommentRenote = isRenote && post.text != nil && post.text != ""
        return isRenote ? (isCommentRenote ? .CommentRenote : .Renote) : .Note
    }
}
