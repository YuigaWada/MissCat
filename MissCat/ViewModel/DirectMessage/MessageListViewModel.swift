//
//  MessageListViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/16.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxCocoa
import RxSwift

class MessageListViewModel: ViewModelType {
    // MARK: I/O
    
    struct Input {
        let dataSource: SenderDataSource
    }
    
    struct Output {
        let users: PublishSubject<[SenderCell.Section]> = .init()
    }
    
    struct State {
        var isLoading: Bool = false
        var hasPrepared: Bool = false
        
        var hasAccounts: Bool {
            return Cache.UserDefaults.shared.getUsers().count > 0
        }
    }
    
    private let input: Input
    let output: Output = .init()
    var state: State = .init()
    
    var cellsModel: [SenderCell.Model] = []
    private lazy var misskey: MisskeyKit? = {
        guard let owner = owner else { return nil }
        return MisskeyKit(from: owner)
    }()
    
    var owner: SecureUser? {
        didSet {
            guard let owner = owner else { return }
            model.change(from: MisskeyKit(from: owner), owner: owner)
        }
    }
    
    private lazy var model: MessageListModel = .init(from: misskey, owner: owner)
    
    private let disposeBag: DisposeBag
    
    // MARK: LifeCycle
    
    init(with input: Input, and disposeBag: DisposeBag) {
        self.input = input
        self.disposeBag = disposeBag
        owner = Cache.UserDefaults.shared.getCurrentUser()
    }
    
    func load() {
        state.hasPrepared = true
        loadHistory().subscribe(onError: { error in
            print(error)
        }, onCompleted: {
            DispatchQueue.main.async {
                self.updateUsers(new: self.cellsModel)
            }
        }, onDisposed: nil).disposed(by: disposeBag)
    }
    
    func removeAll() {
        cellsModel = []
        updateUsers(new: cellsModel)
    }
    
    // MARK: Load
    
//    func loadUntilUsers() -> Observable<SenderCell.Model> {
//        guard let untilId = cellsModel[cellsModel.count - 1].userId else {
//            return Observable.create { _ in
//                Disposables.create()
//            }
//        }
//
//        return loadUsers(untilId: untilId).do(onCompleted: {
//            self.updateUsers(new: self.cellsModel)
//        })
//    }
    
    func loadHistory(untilId: String? = nil) -> Observable<SenderCell.Model> {
        state.isLoading = true
        return model.loadHistory().do(onNext: { cellModel in
            self.cellsModel.append(cellModel)
        }, onCompleted: {
            self.state.isLoading = false
        })
    }
    
    // MARK: Rx
    
    private func updateUsers(new: [SenderCell.Model]) {
        updateUsers(new: [SenderCell.Section(items: new)])
    }
    
    private func updateUsers(new: [SenderCell.Section]) {
        output.users.onNext(new)
    }
}
