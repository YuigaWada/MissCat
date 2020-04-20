//
//  UserListViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/13.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxSwift

class UserListViewModel: ViewModelType {
    // MARK: I/O
    
    struct Input {
        let dataSource: UsersDataSource
        let type: UserListType
        let userId: String?
        let query: String?
        let listId: String?
    }
    
    struct Output {
        let users: PublishSubject<[UserCell.Section]> = .init()
    }
    
    struct State {
        var isLoading: Bool
    }
    
    private let input: Input
    let output: Output = .init()
    var state: State {
        return .init(isLoading: _isLoading)
    }
    
    var cellsModel: [UserCell.Model] = []
    private let model: UserListModel = .init()
    
    private let disposeBag: DisposeBag
    private var hasSkeltonCell: Bool = false
    private var _isLoading: Bool = false
    
    // MARK: LifeCycle
    
    init(with input: Input, and disposeBag: DisposeBag) {
        self.input = input
        self.disposeBag = disposeBag
    }
    
    func setupInitialCell() {
        loadUsers().subscribe(onError: { error in
            print(error)
        }, onCompleted: {
            DispatchQueue.main.async {
                self.updateUsers(new: self.cellsModel)
                self.removeSkeltonCell()
            }
        }, onDisposed: nil).disposed(by: disposeBag)
    }
    
    func setSkeltonCell() {
        guard !hasSkeltonCell else { return }
        
        for _ in 0 ..< 10 {
            let skeltonCellModel = UserCell.Model.fakeSkeltonCell()
            cellsModel.append(skeltonCellModel)
        }
        
        updateUsers(new: cellsModel)
        hasSkeltonCell = true
    }
    
    private func removeSkeltonCell() {
        guard hasSkeltonCell else { return }
        let removed = cellsModel.suffix(cellsModel.count - 10)
        cellsModel = Array(removed)
        
        updateUsers(new: cellsModel)
    }
    
    // MARK: Load
    
    func loadUntilUsers() -> Observable<UserCell.Model> {
        guard let untilId = cellsModel[cellsModel.count - 1].userId else {
            return Observable.create { _ in
                Disposables.create()
            }
        }
        
        return loadUsers(untilId: untilId).do(onCompleted: {
            self.updateUsers(new: self.cellsModel)
        })
    }
    
    func loadUsers(untilId: String? = nil) -> Observable<UserCell.Model> {
        let option = UserListModel.LoadOption(type: input.type,
                                              userId: input.userId,
                                              query: input.query,
                                              listId: input.listId,
                                              untilId: untilId)
        
        _isLoading = true
        return model.loadUsers(with: option).do(onNext: { cellModel in
            self.cellsModel.append(cellModel)
        }, onCompleted: {
            self._isLoading = false
        })
    }
    
    // MARK: Rx
    
    private func updateUsers(new: [UserCell.Model]) {
        updateUsers(new: [UserCell.Section(items: new)])
    }
    
    private func updateUsers(new: [UserCell.Section]) {
        output.users.onNext(new)
    }
}
