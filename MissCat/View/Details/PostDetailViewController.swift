//
//  PostDetailView.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/12/01.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxDataSources
import RxSwift
import UIKit

class PostDetailViewController: NoteDisplay, UITableViewDelegate, FooterTabBarDelegate {
    @IBOutlet weak var mainTableView: UITableView!
    
    private var viewModel: PostDetailViewModel?
    private let disposeBag = DisposeBag()
    private var loadCompleted: Bool = false
    private var cellHeightCache: [String: CGFloat] = [:] // String → identifier
    
    private var wasReplyTarget: Bool = false
    private var wasOnOtherNote: Bool = false
    
    var mainItem: NoteCell.Model? {
        didSet {
            guard let item = mainItem else { return }
            
            wasReplyTarget = item.isReplyTarget
            wasOnOtherNote = item.onOtherNote
            
            item.isReplyTarget = false
            item.onOtherNote = false
            viewModel?.setItem(item)
        }
    }
    
    // MARK: Life Cycle
    
    override func loadView() {
        super.loadView()
        setupTableView()
        setTheme()
        bindTheme()
        
        self.viewModel = .init(disposeBag: disposeBag)
        
        guard let viewModel = viewModel else { return }
        viewModel.dataSource = setupDataSource()
        binding(dataSource: viewModel.dataSource)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        mainItem?.isReplyTarget = wasReplyTarget
        mainItem?.onOtherNote = wasOnOtherNote // 投稿モデルは参照渡しなので、viewWillDisappearで元に戻す
    }
    
    // MARK: Design
    
    private func bindTheme() {
        let theme = Theme.shared.theme
        theme.map { $0.colorPattern.ui.base }.bind(to: view.rx.backgroundColor).disposed(by: disposeBag)
        theme.map { $0.colorPattern.ui.base }.bind(to: mainTableView.rx.backgroundColor).disposed(by: disposeBag)
    }
    
    private func setTheme() {
        if let baseColor = Theme.shared.currentModel?.colorPattern.ui.base {
            view.backgroundColor = baseColor
            mainTableView.backgroundColor = baseColor
        }
    }
    
    /// ステータスバーの文字色
    override var preferredStatusBarStyle: UIStatusBarStyle {
        let currentColorMode = Theme.shared.currentModel?.colorMode ?? .light
        return currentColorMode == .light ? UIStatusBarStyle.default : UIStatusBarStyle.lightContent
    }
    
    // MARK: Setup TableView
    
    private func setupTableView() {
        mainTableView.register(UINib(nibName: "NoteCell", bundle: nil), forCellReuseIdentifier: "NoteCell")
        
        mainTableView.rx.setDelegate(self).disposed(by: disposeBag)
    }
    
    private func setupDataSource() -> NotesDataSource {
        let dataSource = NotesDataSource(
            animationConfiguration: AnimationConfiguration(insertAnimation: .fade, reloadAnimation: .none, deleteAnimation: .fade),
            configureCell: { dataSource, _, indexPath, _ in
                self.setupCell(dataSource, self.mainTableView, indexPath)
            }
        )
        
        return dataSource
    }
    
    private func binding(dataSource: NotesDataSource?) {
        guard let dataSource = dataSource, let viewModel = viewModel else { return }
        
        viewModel.notes
            .bind(to: mainTableView.rx.items(dataSource: dataSource))
            .disposed(by: disposeBag)
    }
    
    // MARK: Setup Cell
    
    private func setupCell(_ dataSource: TableViewSectionedDataSource<NoteCell.Section>, _ tableView: UITableView, _ indexPath: IndexPath) -> UITableViewCell {
        guard let viewModel = viewModel else { return UITableViewCell() }
        
        let index = indexPath.row
        let item = viewModel.cellsModel[index]
        let isDetailMode = item.identity == mainItem?.identity // リプライはDetailModeにしない
        
        guard let noteCell = tableView.dequeueReusableCell(withIdentifier: "NoteCell", for: indexPath) as? NoteCell,
            let owner = item.owner else { return NoteCell() }
        
        let shapedCell = noteCell.transform(with: .init(item: item, isDetailMode: isDetailMode, delegate: self, owner: owner))
        
        shapedCell.nameTextView.renderViewStrings()
        shapedCell.noteView.renderViewStrings()
        
        return shapedCell
    }
    
    // tableViewの負担を軽減するようキャッシュを活用
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let viewModel = viewModel else { return UITableView.automaticDimension }
        
        let index = indexPath.row
        let id = viewModel.cellsModel[index].identity
        
        guard let height = cellHeightCache[id] else { return UITableView.automaticDimension }
        return height
    }
    
    // セル選択後すぐに選択をキャンセルする + タップ処理
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath as IndexPath, animated: true)
        
        guard let viewModel = viewModel else { return }
        let index = indexPath.row
        let item = viewModel.cellsModel[index]
        
        let isTappable = item.identity != mainItem?.identity
        if isTappable {
            homeViewController?.tappedCell(item: item)
        }
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
        //            self.viewModel.loadUntilNotes() {
        //                self.loadCompleted = true //セル更新最中に多重更新されないように
        //            }
    }
    
    // MARK: Delegate
    
    override func tappedLink(text: String, owner: SecureUser) {
        let (linkType, value) = text.analyzeHyperLink()
        switch linkType {
        case .url:
            homeViewController?.openLink(url: value)
        case .user:
            homeViewController?.move2Profile(userId: value, owner: owner)
        case .hashtag:
            navigationController?.popViewController(animated: true)
            homeViewController?.emulateFooterTabTap(tab: .home)
            homeViewController?.searchHashtag(tag: value)
        }
    }
    
    func tappedNotifications() {
        mainTableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
    }
    
    func tappedHome() {}
    
    func tappedPost() {}
    
    func tappedDM() {}
    
    func tappedProfile() {}
}
