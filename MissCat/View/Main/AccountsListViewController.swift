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
    
    var homeViewController: HomeViewController?
    private var viewModel: AccountsListViewModel?
    private let disposeBag = DisposeBag()
    
    // MARK: Life Cycle
    
    override func loadView() {
        super.loadView()
        setupTableView()
        bindTheme()
        setTheme()
        
        self.viewModel = .init(with: nil, and: disposeBag)
        
        guard let viewModel = viewModel else { return }
        viewModel.dataSource = setupDataSource()
        binding(dataSource: viewModel.dataSource)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        view.deselectCell(on: mainTableView)
        
        if let viewModel = viewModel, viewModel.state.hasAccounts, !viewModel.state.hasPrepared {
            viewModel.initialLoad()
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
        mainTableView.rowHeight = UITableView.automaticDimension
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
        
        output.accounts.asDriver(onErrorDriveWith: Driver.empty())
            .drive(mainTableView.rx.items(dataSource: dataSource))
            .disposed(by: disposeBag)
    }
    
    // MARK: Setup Cell
    
    private func setupCell(_ dataSource: TableViewSectionedDataSource<AccountCell.Section>, _ tableView: UITableView, _ indexPath: IndexPath) -> UITableViewCell {
        guard let viewModel = viewModel else { return AccountCell() }
        
        let index = indexPath.row
        let item = viewModel.accounts[index].items[0]
        
        guard let noteCell = tableView.dequeueReusableCell(withIdentifier: "AccountCell", for: indexPath) as? AccountCell
        else { return AccountCell() }
        
        let shapedCell = noteCell.transform(with: .init(user: item.owner))
        
        return shapedCell
    }
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let index = indexPath.row
        guard let user = viewModel?.accounts[index].items[0].owner else { return }
        
        homeViewController?.move2Profile(userId: user.userId, owner: user)
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return section != 0 ? 30 : 0 // 先頭のヘッダー(余白)は表示しない
    }
    
    // ヘッダーを透明にして空白を作る
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let marginView = UIView()
        marginView.backgroundColor = .clear
        return marginView
    }
}
