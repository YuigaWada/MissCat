//
//  MessageListViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/16.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxCocoa
import RxSwift
import MisskeyKit

class MessageListViewModel: ViewModelType {
    // MARK: I/O
    
    struct Input {
        let owner: SecureUser
        let dataSource: SenderDataSource
    }
    
    struct Output {
        let users: PublishSubject<[SenderCell.Section]> = .init()
    }
    
    struct State {
        var isLoading: Bool
    }
    
    private let input: Input
    let output: Output = .init()
    var state: State {
        return .init(isLoading: _isLoading)
    }
    
    var cellsModel: [SenderCell.Model] = []
    private lazy var misskey = MisskeyKit(from: input.owner)
    private lazy var model: MessageListModel = .init(from: misskey)
    
    private let disposeBag: DisposeBag
    private var _isLoading: Bool = false
    
    // MARK: LifeCycle
    
    init(with input: Input, and disposeBag: DisposeBag) {
        self.input = input
        self.disposeBag = disposeBag
    }
    
    func setupInitialCell() {
        loadHistory().subscribe(onError: { error in
            print(error)
        }, onCompleted: {
            DispatchQueue.main.async {
                self.updateUsers(new: self.cellsModel)
            }
        }, onDisposed: nil).disposed(by: disposeBag)
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
        _isLoading = true
        return model.loadHistory().do(onNext: { cellModel in
            self.cellsModel.append(cellModel)
        }, onCompleted: {
            self._isLoading = false
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
