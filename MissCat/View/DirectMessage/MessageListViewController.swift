//
//  MessageListViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/16.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxCocoa
import RxDataSources
import RxSwift
import UIKit

typealias SenderDataSource = RxTableViewSectionedAnimatedDataSource<SenderCell.Section>
class MessageListViewController: UIViewController, UITableViewDelegate {
    @IBOutlet weak var tableView: UITableView!
    
    var homeViewController: HomeViewController?
    
    private lazy var viewModel: MessageListViewModel = setupViewModel()
    private lazy var dataSource = self.setupDataSource()
    private let disposeBag: DisposeBag = .init()
    
    private var loggedIn: Bool = false
    
    // MARK: LifeCycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupTableView()
        setTheme()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        view.deselectCell(on: tableView)
        
        if viewModel.state.hasAccounts, !viewModel.state.hasPrepared {
            viewModel.load()
        }
    }
    
    private func binding(with viewModel: MessageListViewModel, and dataSource: SenderDataSource?) {
        guard let dataSource = dataSource else { return }
        
        let output = viewModel.output
        output.users.bind(to: tableView.rx.items(dataSource: dataSource)).disposed(by: disposeBag)
    }
    
    private func setTheme() {
        if let colorPattern = Theme.shared.currentModel?.colorPattern.ui {
            view.backgroundColor = colorPattern.base
            tableView.backgroundColor = colorPattern.base
        }
    }
    
    // MARK: Setup
    
    private func setupViewModel() -> MessageListViewModel {
        let input = MessageListViewModel.Input(dataSource: dataSource)
        let viewModel = MessageListViewModel(with: input, and: disposeBag)
        
        binding(with: viewModel, and: dataSource)
        return viewModel
    }
    
    private func setupTableView() {
        tableView.register(UINib(nibName: "SenderCell", bundle: nil), forCellReuseIdentifier: "SenderCell")
        tableView.delegate = self
    }
    
    private func setupDataSource() -> SenderDataSource {
        let dataSource = SenderDataSource(
            animationConfiguration: AnimationConfiguration(insertAnimation: .fade, reloadAnimation: .none, deleteAnimation: .fade),
            configureCell: { dataSource, _, indexPath, _ in
                self.setupCell(dataSource, self.tableView, indexPath)
            }
        )
        
        return dataSource
    }
    
    private func setupCell(_ dataSource: TableViewSectionedDataSource<SenderCell.Section>, _ tableView: UITableView, _ indexPath: IndexPath) -> UITableViewCell {
        let index = indexPath.row
        let item = viewModel.cellsModel[index]
        
        guard let itemCell = tableView.dequeueReusableCell(withIdentifier: "SenderCell", for: indexPath) as? SenderCell else { fatalError("Internal Error.") }
        
        if item.isSkelton {
            return itemCell.transform(isSkelton: true)
        }
        
        let shapedCell = itemCell.transform(with: item)
        shapedCell.nameTextView.renderViewStrings()
        
        return shapedCell
    }
    
    private func getDMViewController(with item: SenderCell.Model) -> DirectMessageViewController {
        guard let owner = Cache.UserDefaults.shared.getCurrentUser() else { return DirectMessageViewController() }
        let dmViewController = DirectMessageViewController()
        
        dmViewController.homeViewController = homeViewController
        dmViewController.setup(userId: item.userId ?? "", groupId: nil, owner: owner)
        return dmViewController
    }
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let index = indexPath.row
        let item = viewModel.cellsModel[index]
        
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(getDMViewController(with: item), animated: true)
    }
}

extension MessageListViewController: NavBarDelegate {
    func changeUser(_ user: SecureUser) {
        guard user.userId != viewModel.owner?.userId else { return } // 同じアカウントへの切り替えを防ぐ
        viewModel.owner = user
        viewModel.removeAll()
        viewModel.load()
    }
    
    func showAccountMenu(sourceRect: CGRect) -> Observable<SecureUser>? {
        return nil
    }
    
    func tappedRightNavButton() {}
}
