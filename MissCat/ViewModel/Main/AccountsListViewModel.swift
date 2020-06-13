//
//  AccountsListViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/06/08.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxCocoa
import RxSwift
import UIKit

class AccountsListViewModel: ViewModelType {
    struct Input {
        let loginTrigger: Observable<Void>
        let editTrigger: Observable<Void>
    }
    
    struct Output {
        let accounts: PublishRelay<[AccountCell.Section]> = .init()
        let showLoginViewTrigger: PublishRelay<Void> = .init()
        let switchEditableTrigger: PublishRelay<Void> = .init()
        let switchNormalTrigger: PublishRelay<Void> = .init()
        let noAccountsTrigger: PublishRelay<Void> = .init()
    }
    
    struct State {
        var isEditing: Bool = false
        var hasPrepared: Bool = false
        var hasAccounts: Bool {
            return Cache.UserDefaults.shared.getUsers().count > 0
        }
    }
    
    private let input: Input
    var output: Output = .init()
    var state: State = .init()
    var dataSource: AccountsListDataSource?
    
    var accounts: [AccountCell.Section] = []
    private let disposeBag: DisposeBag
    private lazy var model = AccountsListModel()
    
    init(with input: Input, and disposeBag: DisposeBag) {
        self.input = input
        self.disposeBag = disposeBag
        transform()
    }
    
    func load() {
        let users = model.getUsers()
        
        accounts.removeAll() // 初期化しておく
        state.hasPrepared = true
        users.forEach { user in
            let account = AccountCell.Model(owner: user)
            let accountSection = AccountCell.Section(items: [account])
            
            accounts.append(accountSection)
        }
        
        update(accounts)
    }
    
    func delete(index: Int) {
        let user = accounts[index].items[0].owner
        
        // アカウントを削除
        model.removeUser(user: user)
        accounts.remove(at: index)
        update(accounts)
        
        // タブをチェック
        model.checkTabs(for: user)
        
        // アカウントが残っているかチェック
        if accounts.count == 0 {
            output.noAccountsTrigger.accept(())
        }
    }
    
    private func transform() {
        input.editTrigger.subscribe(onNext: {
            if self.state.isEditing {
                self.output.switchNormalTrigger.accept(())
            } else {
                self.output.switchEditableTrigger.accept(())
            }
            self.state.isEditing = !self.state.isEditing
        }).disposed(by: disposeBag)
        
        input.loginTrigger.subscribe(onNext: {
            self.output.showLoginViewTrigger.accept(())
        }).disposed(by: disposeBag)
    }
    
    private func update(_ accounts: [AccountCell.Section]) {
        output.accounts.accept(accounts)
    }
}
