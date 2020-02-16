//
//  TimelineViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/07.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import FloatingPanel
import RxCocoa
import RxDataSources
import RxSwift
import UIKit
import XLPagerTabStrip

public protocol TimelineDelegate { // For HomeViewController
    func tappedCell(item: NoteCell.Model)
    func move2Profile(userId: String)
    func openUserPage(username: String)
    
    func successInitialLoading(_ success: Bool)
    func changedStreamState(success: Bool)
}

typealias NotesDataSource = RxTableViewSectionedAnimatedDataSource<NoteCell.Section>
private typealias ViewModel = TimelineViewModel

class TimelineViewController: UIViewController, UITableViewDelegate, FooterTabBarDelegate, NoteCellDelegate, IndicatorInfoProvider {
    @IBOutlet weak var mainTableView: UITableView!
    @IBOutlet weak var bottomConstraint: NSLayoutConstraint!
    
    private let disposeBag = DisposeBag()
    private var viewModel: TimelineViewModel?
    
    private lazy var refreshControl = UIRefreshControl()
    
    private var loadCompleted: Bool = true
    private var cellHeightCache: [String: CGFloat] = [:] // String → identifier
    private var withNavBar: Bool = true
    private var scrollable: Bool = true
    private var streamConnecting: Bool = false
    
    private lazy var dataSource = self.setupDataSource()
    
    public var homeViewController: TimelineDelegate?
    public var xlTitle: IndicatorInfo? // XLPagerTabStripで用いるtitle
    
    // MARK: Life Cycle
    
    /// 外部からTimelineViewContollerのインスタンスを生成する場合、このメソッドを通じて適切なパラメータをセットしていく
    /// - Parameters:
    ///   - type: TimelineType
    ///   - includeReplies: リプライ含めるか
    ///   - onlyFiles: ファイルのみのタイムラインか
    ///   - userId: 注目するユーザーのuserId
    ///   - listId: 注目するリストのlistId
    ///   - withNavBar: NavBarが必要か
    ///   - scrollable: スクロール可能か
    ///   - loadLimit: 一度に読み込むnoteの量
    ///   - xlTitle: タブに表示する名前
    public func setup(type: TimelineType,
                      includeReplies: Bool? = nil,
                      onlyFiles: Bool? = nil,
                      userId: String? = nil,
                      listId: String? = nil,
                      withNavBar: Bool = true,
                      scrollable: Bool = true,
                      loadLimit: Int = 40,
                      xlTitle: IndicatorInfo? = nil) {
        let input = ViewModel.Input(dataSource: dataSource,
                                    type: type,
                                    includeReplies: includeReplies,
                                    onlyFiles: onlyFiles,
                                    userId: userId,
                                    listId: listId,
                                    loadLimit: loadLimit)
        
        viewModel = ViewModel(with: input, and: disposeBag)
        streamConnecting = type.needsStreaming
        self.xlTitle = xlTitle
        self.withNavBar = withNavBar
        self.scrollable = scrollable
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupTableView()
        setupPullGesture()
        if viewModel == nil {
            setup(type: .Home)
        }
        
        binding(dataSource: dataSource)
        viewModel!.setupInitialCell()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        mainTableView.isScrollEnabled = scrollable
        if let bottomConstraint = bottomConstraint {
            bottomConstraint.isActive = withNavBar
        }
    }
    
    // MARK: Setup TableView
    
    private func setupTableView() {
        mainTableView.register(UINib(nibName: "NoteCell", bundle: nil), forCellReuseIdentifier: "NoteCell")
        mainTableView.register(UINib(nibName: "RenoteeCell", bundle: nil), forCellReuseIdentifier: "RenoteeCell")
        
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
    
    // MARK: Binding
    
    private func binding(dataSource: NotesDataSource?) {
        guard let viewModel = viewModel, let dataSource = dataSource else { return }
        
        let output = viewModel.output
        output.notes.bind(to: mainTableView.rx.items(dataSource: dataSource)).disposed(by: disposeBag)
        
        output.forceUpdateIndex.subscribe(onNext: updateForcibly).disposed(by: disposeBag)
        
        output.finishedLoading.subscribe(onNext: { success in
            guard let homeViewController = self.homeViewController else { return }
            
            homeViewController.successInitialLoading(success)
        }).disposed(by: disposeBag)
        
        output.connectedStream.subscribe(onNext: { success in
            guard let homeViewController = self.homeViewController else { return }
            
            homeViewController.changedStreamState(success: success)
        }).disposed(by: disposeBag)
    }
    
    // MARK: Gesture
    
    private func setupPullGesture() {
        refreshControl.attributedTitle = NSAttributedString(string: "Refresh...")
        refreshControl.addTarget(self, action: #selector(refreshTableView(_:)), for: UIControl.Event.valueChanged)
        
        if !streamConnecting {
            mainTableView.addSubview(refreshControl) // ストリーミングでないときだけ
        }
    }
    
    @objc func refreshTableView(_ sender: Any) {
        guard let viewModel = viewModel else { return }
        
        viewModel.loadUntilNotes {
            DispatchQueue.main.async { self.refreshControl.endRefreshing() }
        }
    }
    
    // MARK: Setup Cell
    
    private func setupCell(_ dataSource: TableViewSectionedDataSource<NoteCell.Section>, _ tableView: UITableView, _ indexPath: IndexPath) -> UITableViewCell {
        guard let viewModel = viewModel else { fatalError("Internal Error.") }
        
        let index = indexPath.row
        let item = viewModel.cellsModel[index]
        
        // View側で NoteCell / RenoteeCellを区別する
        if item.isRenoteeCell {
            guard let renoteeCell = tableView.dequeueReusableCell(withIdentifier: "RenoteeCell", for: indexPath) as? RenoteeCell
            else { return RenoteeCell() }
            
            renoteeCell.setRenotee(item.renotee ?? "")
            return renoteeCell
        }
        
        // 通常のcellをつくる
        guard let itemCell = tableView.dequeueReusableCell(withIdentifier: "NoteCell", for: indexPath) as? NoteCell else { fatalError("Internal Error.") }
        
        let shapedCell = viewModel.getCell(cell: itemCell, item: item)
        shapedCell.delegate = self
        
        return shapedCell
    }
    
    private func showDetailView(item: NoteCell.Model) {
        guard let homeViewController = self.homeViewController else { return }
        
        var item = item
        item.isReplyTarget = false // NoteCellのReplyIndicatorを消す
        homeViewController.tappedCell(item: item) // 画面遷移に関してはすべてHomeViewControllerが受け持つ
    }
    
    // MARK: TableView Delegate
    
    //tableViewの負担を軽減するようキャッシュを活用
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        let index = indexPath.row
        guard let viewModel = viewModel, index < viewModel.cellsModel.count else { return UITableView.automaticDimension }
        
        let id = viewModel.cellsModel[index].identity
        guard let height = self.cellHeightCache[id] else {
            return viewModel.cellsModel[index].isRenoteeCell ? 25 : UITableView.automaticDimension
        }
        return height
    }
    
    // estimatedHeightForRowAtとheightForRowAtてどっちもいるのか？
    // TODO: リアクションがつくと、高さが更新されずtextViewが潰れる
//    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
//        guard let viewModel = viewModel else { return UITableView.automaticDimension }
//
//        let index = indexPath.row
//        let id = viewModel.cellsModel[index].identity
//
//        guard let height = self.cellHeightCache[id] else {
//            return viewModel.cellsModel[index].isRenoteeCell ? 25 : UITableView.automaticDimension
//        }
//        return height
//    }
    
    // セル選択後すぐに選択をキャンセルする & ReactionGenCellを消す
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let viewModel = viewModel else { return }
        
        let index = indexPath.row
        
        showDetailView(item: viewModel.cellsModel[index])
        tableView.deselectRow(at: indexPath as IndexPath, animated: true)
        
        // TODO: renoteeCellをタップしたらrenote先までタップしたことにする
        //tableView.selectRow(at: <#T##IndexPath?#>, animated: true, scrollPosition: .none)
    }
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let viewModel = viewModel else { return }
        
        let index = indexPath.row
        let cellModel = viewModel.cellsModel[index]
        let id = cellModel.identity
        
        // 再計算しないでいいようにセルの高さをキャッシュ
        if cellHeightCache.keys.contains(id) != true {
            cellHeightCache[id] = cellModel.isRenoteeCell ? 25 : cell.frame.height
        }
        
        // 下位20cellsでセル更新
        guard loadCompleted, viewModel.state.cellCount - indexPath.row < 10 else { return }
        
        print("loadUntilNotes...")
        loadCompleted = false
        viewModel.loadUntilNotes {
            self.loadCompleted = true // セル更新最中に多重更新されないように
        }
    }
    
    // MARK: Utilities
    
    // 強制的にセルを更新する
    private func updateForcibly(index: Int) {
        let row = IndexPath(row: index, section: 0)
        DispatchQueue.main.async { self.mainTableView.reloadRows(at: [row], with: .none) }
    }
    
    private func getViewController(name: String) -> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyboard.instantiateViewController(withIdentifier: name)
        
        return viewController
    }
    
    // MARK: FooterTabBar Delegate
    
    func tappedHome() {
        mainTableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
    }
    
    func tappedNotifications() {}
    
    func tappedPost() {}
    
    func tappedFav() {}
    
    func tappedProfile() {}
    
    // MARK: NoteCell Delegate
    
    func tappedReply() {}
    
    func tappedRenote() {}
    
    func tappedReaction(noteId: String, iconUrl: String?, displayName: String, username: String, note: NSAttributedString, hasFile: Bool, hasMarked: Bool) {
        presentReactionGen(noteId: noteId, iconUrl: iconUrl, displayName: displayName, username: username, note: note, hasFile: hasFile, hasMarked: hasMarked)
    }
    
    func tappedOthers() {}
    
    func tappedLink(text: String) {
        guard let viewModel = viewModel else { return }
        
        let (linkType, value) = text.analyzeHyperLink()
        
        switch linkType {
        case "URL":
            openLink(url: value)
        case "User":
            openUser(username: value)
        default:
            break
        }
    }
    
    func openUser(username: String) {
        guard let homeViewController = self.homeViewController else { return }
        homeViewController.openUserPage(username: username)
    }
    
    func move2Profile(userId: String) {
        guard let homeViewController = self.homeViewController else { return }
        homeViewController.move2Profile(userId: userId)
    }
    
    // MARK: XLPagerTabStrip delegate
    
    func indicatorInfo(for pagerTabStripController: PagerTabStripViewController) -> IndicatorInfo {
        return xlTitle ?? "Home"
    }
}
