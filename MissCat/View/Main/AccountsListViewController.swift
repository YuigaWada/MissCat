//
//  AccountsListViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/06/08.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxCocoa
import RxDataSources
import RxSwift
import UIKit

typealias AccountsListDataSource = RxTableViewSectionedAnimatedDataSource<AccountCell.Section>
class AccountsListViewController: UIViewController, UITableViewDelegate {
    @IBOutlet weak var mainTableView: UITableView!
    @IBOutlet weak var loginButton: UIButton!
    @IBOutlet weak var editButton: UIButton!
    
    var homeViewController: HomeViewController?
    private var viewModel: AccountsListViewModel?
    private let disposeBag = DisposeBag()
    
    private var deleteTriggerDisposables: [Int: Disposable] = [:]
    
    // MARK: Life Cycle
    
    override func loadView() {
        super.loadView()
        setupTableView()
        bindTheme()
        setTheme()
        
        let input = AccountsListViewModel.Input(loginTrigger: loginButton.rx.tap.asObservable(),
                                                editTrigger: editButton.rx.tap.asObservable())
        self.viewModel = AccountsListViewModel(with: input, and: disposeBag)
        
        guard let viewModel = viewModel else { return }
        viewModel.dataSource = setupDataSource()
        binding(dataSource: viewModel.dataSource)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        view.deselectCell(on: mainTableView)
        
        if let viewModel = viewModel, viewModel.state.hasAccounts, !viewModel.state.hasPrepared {
            viewModel.load()
        }
    }
    
    // MARK: Design
    
    private func bindTheme() {
        let theme = Theme.shared.theme
        
        theme.map { $0.colorPattern.ui }.subscribe(onNext: { colorPattern in
            self.view.backgroundColor = colorPattern.base
            self.mainTableView.backgroundColor = colorPattern.base
        }).disposed(by: disposeBag)
    }
    
    private func setTheme() {
        if let colorPattern = Theme.shared.currentModel?.colorPattern.ui {
            view.backgroundColor = colorPattern.base
            mainTableView.backgroundColor = colorPattern.base
        }
    }
    
    // MARK: Setup TableView
    
    private func setupTableView() {
        mainTableView.register(UINib(nibName: "AccountCell", bundle: nil), forCellReuseIdentifier: "AccountCell")
        
        mainTableView.rx.setDelegate(self).disposed(by: disposeBag)
//        mainTableView.rowHeight = UITableView.automaticDimension
        mainTableView.rowHeight = 120
    }
    
    private func setupDataSource() -> AccountsListDataSource {
        let dataSource = AccountsListDataSource(
            animationConfiguration: AnimationConfiguration(insertAnimation: .fade, reloadAnimation: .none, deleteAnimation: .fade),
            configureCell: { dataSource, _, indexPath, _ in
                self.setupCell(dataSource, self.mainTableView, indexPath)
            }
        )
        
        return dataSource
    }
    
    private func binding(dataSource: AccountsListDataSource?) {
        guard let dataSource = dataSource, let output = viewModel?.output else { return }
        
        output.accounts
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(mainTableView.rx.items(dataSource: dataSource))
            .disposed(by: disposeBag)
        
        output.showLoginViewTrigger
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: {
                self.showLoginView()
            })
            .disposed(by: disposeBag)
        
        output.switchEditableTrigger
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: {
                self.switchEditable()
            })
            .disposed(by: disposeBag)
        
        output.switchNormalTrigger
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: {
                self.switchNormal()
            })
            .disposed(by: disposeBag)
        
        output.noAccountsTrigger
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: {
                self.logout()
            })
            .disposed(by: disposeBag)
        
        output.relaunchTabsTrigger
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: {
                self.homeViewController?.relaunchView(start: .profile)
            })
            .disposed(by: disposeBag)
    }
    
    private func logout() {
        guard let startViewController = getViewController(name: "start") as? StartViewController else { return }
        
        Cache.shared.resetMyCache()
        Theme.shared.removeAllTabs()
        
        startViewController.reloadTrigger.subscribe(onNext: {
            self.homeViewController?.relaunchView(start: .main) // すべてのviewをrelaunchする
        }).disposed(by: disposeBag)
        
        presentOnFullScreen(startViewController, animated: true, completion: nil)
    }
    
    private func showLoginView() {
        guard let startViewController = getViewController(name: "start") as? StartViewController else { return }
        
        startViewController.reloadTrigger.subscribe(onNext: {
            self.viewModel?.load()
        }).disposed(by: disposeBag)
        navigationController?.pushViewController(startViewController, animated: true)
    }
    
    private func getViewController(name: String) -> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyboard.instantiateViewController(withIdentifier: name)
        
        return viewController
    }
    
    private func switchEditable() {
        mainTableView.visibleCells
            .compactMap { $0 as? AccountCell }
            .forEach { $0.changeState(.editable) }
    }
    
    private func switchNormal() {
        mainTableView.visibleCells
            .compactMap { $0 as? AccountCell }
            .forEach { $0.changeState(.normal) }
    }
    
    private func delete(index: Int, viewModel: AccountsListViewModel) {
        showAlert(title: "", message: "本当に削除しますか？", yesOption: "はい") { yes in
            guard yes else { return }
            viewModel.delete(index: index)
        }
    }
    
    // MARK: Setup Cell
    
    private func setupCell(_ dataSource: TableViewSectionedDataSource<AccountCell.Section>, _ tableView: UITableView, _ indexPath: IndexPath) -> UITableViewCell {
        guard let viewModel = viewModel else { return AccountCell() }
        
        let index = indexPath.section
        let item = viewModel.accounts[index].items[0]
        
        guard let accountCell = tableView.dequeueReusableCell(withIdentifier: "AccountCell", for: indexPath) as? AccountCell
        else { return AccountCell() }
        
        let shapedCell = accountCell.transform(with: .init(user: item.owner))
        
        shapedCell.selectionStyle = .none
        // 購読し直す
        let disposable = shapedCell.deleteTrigger.subscribe(onNext: {
            self.delete(index: index, viewModel: viewModel)
        })
        
        if let oldDisposable = deleteTriggerDisposables.removeValue(forKey: index) { // すでに購読していた場合は破棄する
            oldDisposable.dispose()
        }
        
        deleteTriggerDisposables[index] = disposable
        return shapedCell
    }
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return 120
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let index = indexPath.section
        guard let user = viewModel?.accounts[index].items[0].owner else { return }
        
        homeViewController?.move2Profile(userId: user.userId, owner: user)
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return section != 0 ? 10 : 0 // 先頭のヘッダー(余白)は表示しない
    }
    
    // ヘッダーを透明にして空白を作る
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let marginView = UIView()
        marginView.backgroundColor = .clear
        return marginView
    }
}

extension AccountsListViewController: NavBarDelegate {
    func changeUser(_ user: SecureUser) {}
    
    func showAccountMenu(sourceRect: CGRect) -> Observable<SecureUser>? {
        return nil
    }
    
    func tappedRightNavButton() {}
}
