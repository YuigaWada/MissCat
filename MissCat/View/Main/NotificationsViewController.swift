//
//  NotificationsViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/24.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxCocoa
import RxDataSources
import RxSwift
import UIKit

typealias NotificationDataSource = RxTableViewSectionedAnimatedDataSource<NotificationCell.Section>
class NotificationsViewController: NoteDisplay, UITableViewDelegate, FooterTabBarDelegate {
    @IBOutlet weak var mainTableView: MissCatTableView!
    
    private var viewModel: NotificationsViewModel?
    private let disposeBag = DisposeBag()
    private var loadCompleted: Bool = true
    private var cellHeightCache: [String: CGFloat] = [:] // String → identifier
    
    private var loggedIn: Bool = false
    private var hasApiKey: Bool {
        guard let apiKey = Cache.UserDefaults.shared.getCurrentLoginedApiKey() else { return false }
        return !apiKey.isEmpty
    }
    
    // MARK: Life Cycle
    
    override func loadView() {
        super.loadView()
        setupTableView()
        bindTheme()
        setTheme()
        
        self.viewModel = .init(disposeBag: disposeBag)
        
        guard let viewModel = viewModel else { return }
        viewModel.dataSource = setupDataSource()
        binding(dataSource: viewModel.dataSource)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        view.deselectCell(on: mainTableView)
        
        if !loggedIn, hasApiKey {
            loggedIn = true
            viewModel?.initialLoad()
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
        mainTableView.register(UINib(nibName: "NotificationCell", bundle: nil), forCellReuseIdentifier: "NotificationCell")
        mainTableView.register(UINib(nibName: "NoteCell", bundle: nil), forCellReuseIdentifier: "NoteCell")
        
        mainTableView.rx.setDelegate(self).disposed(by: disposeBag)
        mainTableView.lockScroll = Observable.of(false)
    }
    
    private func setupDataSource() -> NotificationDataSource {
        let dataSource = NotificationDataSource(
            animationConfiguration: AnimationConfiguration(insertAnimation: .fade, reloadAnimation: .none, deleteAnimation: .fade),
            configureCell: { dataSource, _, indexPath, _ in
                self.setupCell(dataSource, self.mainTableView, indexPath)
            }
        )
        
        return dataSource
    }
    
    private func binding(dataSource: NotificationDataSource?) {
        guard let dataSource = dataSource, let viewModel = viewModel else { return }
        
        viewModel.notes.asDriver(onErrorDriveWith: Driver.empty())
            .drive(mainTableView.rx.items(dataSource: dataSource))
            .disposed(by: disposeBag)
    }
    
    // MARK: Setup Cell
    
    private func setupCell(_ dataSource: TableViewSectionedDataSource<NotificationCell.Section>, _ tableView: UITableView, _ indexPath: IndexPath) -> UITableViewCell {
        guard let viewModel = viewModel else { return UITableViewCell() }
        
        let index = indexPath.row
        let item = viewModel.cellsModel[index]
        
        if item.type == .reply || item.type == .mention || item.type == .quote {
            guard let noteCell = tableView.dequeueReusableCell(withIdentifier: "NoteCell", for: indexPath) as? NoteCell, let replyNote = item.replyNote
            else { return NoteCell() }
            
            let shapedCell = noteCell.transform(with: .init(item: replyNote, delegate: self))
            
            shapedCell.noteView.renderViewStrings()
            shapedCell.nameTextView.renderViewStrings()
            
            return shapedCell
        } else if item.type == .reaction || item.type == .renote || item.type == .follow {
            guard let notificationCell = tableView.dequeueReusableCell(withIdentifier: "NotificationCell", for: indexPath) as? NotificationCell
            else { return NotificationCell() }
            
            let shapedCell = notificationCell.shapeCell(item: item)
            shapedCell.delegate = self
            shapedCell.nameTextView.renderViewStrings()
            
            return shapedCell
        }
        
        return UITableViewCell()
    }
    
    // tableViewの負担を軽減するようキャッシュを活用
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let viewModel = viewModel else { return UITableView.automaticDimension }
        
        let index = indexPath.row
        let id = viewModel.cellsModel[index].identity
        
        guard let height = cellHeightCache[id] else { return UITableView.automaticDimension }
        return height
    }
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let viewModel = viewModel else { return }
        
        let index = indexPath.row
        let id = viewModel.cellsModel[index].identity
        
        // 再計算しないでいいようにセルの高さをキャッシュ
        if cellHeightCache.keys.contains(id) != true {
            cellHeightCache[id] = cell.frame.height
        }
        
        // 下位20cellsでセル更新
        guard loadCompleted, viewModel.cellCount - indexPath.row < 10 else { return }
        
        print("loadUntilNotes...")
        loadCompleted = false
        viewModel.loadUntilNotification {
            self.loadCompleted = true // セル更新最中に多重更新されないように
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let index = indexPath.row
        
        guard let cellModel = viewModel?.cellsModel[index],
            let replyNote = cellModel.replyNote,
            cellModel.type == .mention || cellModel.type == .reply || cellModel.type == .quote else { return }
        showDetailView(item: replyNote)
    }
    
    private func showDetailView(item: NoteCell.Model) {
        guard let homeViewController = self.homeViewController else { return }
        
        let item = item
        item.isReplyTarget = false // NoteCellのReplyIndicatorを消す
        homeViewController.tappedCell(item: item) // 画面遷移に関してはすべてHomeViewControllerが受け持つ
    }
    
    // MARK: Delegate
    
    func tappedNotifications() {
        let zeroIndexPath = IndexPath(row: 0, section: 0)
        
        // セルが存在しないと落ちるので制約をつける
        if mainTableView.numberOfSections > zeroIndexPath.section,
            mainTableView.numberOfRows(inSection: zeroIndexPath.section) > zeroIndexPath.row {
            mainTableView.scrollToRow(at: zeroIndexPath, at: .top, animated: true)
        }
    }
    
    func tappedHome() {}
    
    func tappedPost() {}
    
    func tappedDM() {}
    
    func tappedProfile() {}
}
