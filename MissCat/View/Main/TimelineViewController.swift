//
//  TimelineViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/07.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import AVKit
import FloatingPanel
import RxCocoa
import RxDataSources
import RxSwift
import UIKit
import XLPagerTabStrip

protocol TimelineDelegate { // For HomeViewController
    func tappedCell(item: NoteCell.Model)
    func move2Profile(userId: String, owner: SecureUser)
    func openUserPage(username: String, owner: SecureUser)
    func openSettings()
    func openPost(item: NoteCell.Model, type: PostViewController.PostType)
    
    func successInitialLoading(_ success: Bool)
    func changedStreamState(success: Bool)
    func showNotificationBanner(icon: NotificationBanner.IconType, notification: String)
}

typealias NotesDataSource = RxTableViewSectionedAnimatedDataSource<NoteCell.Section>
private typealias ViewModel = TimelineViewModel

class TimelineViewController: NoteDisplay, UITableViewDelegate, FooterTabBarDelegate, IndicatorInfoProvider {
    @IBOutlet weak var mainTableView: MissCatTableView!
    @IBOutlet weak var bottomConstraint: NSLayoutConstraint!
    
    private var topShadow: CALayer?
    
    private let disposeBag = DisposeBag()
    private var viewModel: TimelineViewModel?
    
    private lazy var refreshControl = UIRefreshControl()
    
    private var cellHeightCache: [String: CGFloat] = [:] // String → identifier
    private var loadLimit: Int = 40
    
    private var withNavBar: Bool = true
    private var scrollable: Bool = true
    private var withTopShadow: Bool = false
    private var streamConnecting: Bool = false
    
    private lazy var dataSource = self.setupDataSource()
    
    var xlTitle: IndicatorInfo? // XLPagerTabStripで用いるtitle
    
    // MARK: Life Cycle
    
    /// 外部からTimelineViewContollerのインスタンスを生成する場合、このメソッドを通じて適切なパラメータをセットしていく
    /// - Parameters:
    ///   - owner: TLに紐付けられたユーザーのデータ
    ///   - type: TimelineType
    ///   - includeReplies: リプライ含めるか
    ///   - onlyFiles: ファイルのみのタイムラインか
    ///   - userId: 注目するユーザーのuserId
    ///   - listId: 注目するリストのlistId
    ///   - query: 検索クエリ
    ///   - withNavBar: NavBarが必要か
    ///   - scrollable: スクロール可能か
    ///   - lockScroll: スクロールを固定するかどうか
    ///   - loadLimit: 一度に読み込むnoteの量
    ///   - xlTitle: タブに表示する名前
    func setup(owner: SecureUser,
               type: TimelineType,
               includeReplies: Bool? = nil,
               onlyFiles: Bool? = nil,
               userId: String? = nil,
               listId: String? = nil,
               query: String? = nil,
               withNavBar: Bool = true,
               scrollable: Bool = true,
               lockScroll: Bool = true,
               withTopShadow: Bool = false,
               loadLimit: Int = 40,
               xlTitle: IndicatorInfo? = nil) {
        let input = ViewModel.Input(owner: owner,
                                    dataSource: dataSource,
                                    type: type,
                                    includeReplies: includeReplies,
                                    onlyFiles: onlyFiles,
                                    userId: userId,
                                    listId: listId,
                                    query: query,
                                    lockScroll: lockScroll,
                                    loadLimit: loadLimit)
        
        viewModel = ViewModel(with: input, and: disposeBag)
        streamConnecting = type.needsStreaming
        
        self.xlTitle = xlTitle
        self.withNavBar = withNavBar
        self.scrollable = scrollable
        self.loadLimit = loadLimit
        self.withTopShadow = withTopShadow
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupTableView()
        setupPullGesture()
        
        binding(dataSource: dataSource)
        setupTopShadow()
        bindTheme()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        view.deselectCell(on: mainTableView)
        
        if let viewModel = viewModel, viewModel.state.hasAccounts, !viewModel.state.hasSkeltonCell {
            viewModel.setupInitialCell()
            viewModel.setSkeltonCell()
        }
        
        setTheme()
        
        if let bottomConstraint = bottomConstraint {
            bottomConstraint.isActive = withNavBar
        }
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
    
    // MARK: Setup TableView
    
    private func setupTableView() {
        mainTableView.register(UINib(nibName: "NoteCell", bundle: nil), forCellReuseIdentifier: "NoteCell")
        mainTableView.register(UINib(nibName: "RenoteeCell", bundle: nil), forCellReuseIdentifier: "RenoteeCell")
        mainTableView.register(UINib(nibName: "PromotionCell", bundle: nil), forCellReuseIdentifier: "PromotionCell")
        
        mainTableView.rx.setDelegate(self).disposed(by: disposeBag)
        mainTableView.isScrollEnabled = false
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
            
            self.mainTableView.isScrollEnabled = self.scrollable
        }).disposed(by: disposeBag)
        
        output.connectedStream.subscribe(onNext: { success in
            guard let homeViewController = self.homeViewController else { return }
            homeViewController.changedStreamState(success: success)
        }).disposed(by: disposeBag)
        
        output.reserveLockTrigger.subscribe(onNext: { _ in
            self.mainTableView.reserveLock() // 次にセルがupdateされた時にスクロールを固定し直す
        }).disposed(by: disposeBag)
        
        mainTableView.lockScroll = output.lockTableScroll.asObservable()
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
        
        //        viewModel.loadUntilNotes {
        //            DispatchQueue.main.async { self.refreshControl.endRefreshing() }
        //        }
    }
    
    // MARK: Setup Cell
    
    private func setupCell(_ dataSource: TableViewSectionedDataSource<NoteCell.Section>, _ tableView: UITableView, _ indexPath: IndexPath) -> UITableViewCell {
        guard let viewModel = viewModel else { fatalError("Internal Error.") }
        
        let index = indexPath.row
        let item = viewModel.cellsModel[index]
        
        // View側で NoteCell / RenoteeCell / PromotionCell を区別する
        if item.type == .promote {
            let prCell = tableView.dequeueReusableCell(withIdentifier: "PromotionCell", for: indexPath)
            prCell.selectionStyle = UITableViewCell.SelectionStyle.none
            return prCell
        } else if item.type == .renotee {
            guard let renoteeCell = tableView.dequeueReusableCell(withIdentifier: "RenoteeCell", for: indexPath) as? RenoteeCell
            else { return RenoteeCell() }
            
            renoteeCell.selectionStyle = UITableViewCell.SelectionStyle.none
            renoteeCell.setRenotee(item.renotee ?? "")
            
            renoteeCell.setTapGesture(disposeBag) {
                self.openUser(username: item.noteEntity.username, owner: viewModel.state.owner)
            }
            
            return renoteeCell
        }
        
        // 通常のcellをつくる
        guard let itemCell = tableView.dequeueReusableCell(withIdentifier: "NoteCell", for: indexPath) as? NoteCell else { fatalError("Internal Error.") }
        
        let shapedCell = itemCell.transform(with: .init(item: item,
                                                        delegate: self,
                                                        owner: viewModel.state.owner))
        
        shapedCell.nameTextView.renderViewStrings()
        shapedCell.noteView.renderViewStrings()
        
        return shapedCell
    }
    
    private func showDetailView(item: NoteCell.Model) {
        guard let homeViewController = self.homeViewController else { return }
        
        let item = item
        homeViewController.tappedCell(item: item) // 画面遷移に関してはすべてHomeViewControllerが受け持つ
    }
    
    // MARK: TableView Delegate
    
    // tableViewの負担を軽減するようキャッシュを活用
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        let index = indexPath.row
        guard let viewModel = viewModel, index < viewModel.cellsModel.count else { return UITableView.automaticDimension }
        
        let id = viewModel.cellsModel[index].identity
        guard let height = cellHeightCache[id] else {
            return viewModel.cellsModel[index].type == .renotee ? 25 : UITableView.automaticDimension
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
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let viewModel = viewModel else { return }
        let index = indexPath.row
        showDetailView(item: viewModel.cellsModel[index])
    }
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let viewModel = viewModel else { return }
        
        let index = indexPath.row
        let cellModel = viewModel.cellsModel[index]
        let id = cellModel.identity
        
        // 再計算しないでいいようにセルの高さをキャッシュ
        if cellHeightCache.keys.contains(id) != true {
            cellHeightCache[id] = cellModel.type == .renotee || cellModel.type == .promote ? 25 : cell.frame.height
        }
        
        // 下位4分の1のcellでセル更新
        let state = viewModel.state
        guard !state.isLoading, state.cellCount - indexPath.row < loadLimit / 4 else { return } //  state.cellCompleted,
        
        print("loadUntilNotes...")
        viewModel.loadUntilNotes().subscribe(onError: { error in
            if let error = error as? TimelineModel.NotesLoadingError, error == .NotesEmpty { return }
            self.homeViewController?.showNotificationBanner(icon: .Failed, notification: error.description)
        }).disposed(by: disposeBag)
    }
    
    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        let index = indexPath.row
        guard let item = viewModel?.cellsModel[index] else { return indexPath }
        
        if item.type == .promote { //  PromotionCellはタップできないように
            return nil
        }
        
        return indexPath
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        topShadow?.isHidden = scrollView.contentOffset.y <= 0
    }
    
    // MARK: Utilities
    
    // 強制的にセルを更新する
    private func updateForcibly(index: Int) {
        let row = IndexPath(row: index, section: 0)
        DispatchQueue.main.async {
            self.mainTableView.performBatchUpdates({ // スクロール位置を固定 (#MissCatTableView.performBatchUpdatesを参考に)
                self.mainTableView.reloadRows(at: [row], with: .none)
            })
        }
    }
    
    private func getViewController(name: String) -> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyboard.instantiateViewController(withIdentifier: name)
        
        return viewController
    }
    
    private func setupTopShadow() {
        guard withTopShadow,
            let target = mainTableView else { return }
        
        let path = UIBezierPath(rect: CGRect(x: -5.0, y: -5.0, width: target.bounds.size.width + 5.0, height: 3.0))
        let innerLayer = CALayer()
        innerLayer.frame = target.bounds
        innerLayer.masksToBounds = true
        innerLayer.shadowColor = UIColor.black.cgColor
        innerLayer.shadowOffset = CGSize(width: 2.5, height: 2.5)
        innerLayer.shadowOpacity = 0.5
        innerLayer.isHidden = true
        innerLayer.shadowPath = path.cgPath
        view.layer.addSublayer(innerLayer)
        
        topShadow = innerLayer
    }
    
    // MARK: FooterTabBar Delegate
    
    func tappedHome() {
        guard let mainTableView = mainTableView else { return }
        let zeroIndexPath = IndexPath(row: 0, section: 0)
        
        // セルが存在しないと落ちるので制約をつける
        if mainTableView.numberOfSections > zeroIndexPath.section,
            mainTableView.numberOfRows(inSection: zeroIndexPath.section) > zeroIndexPath.row {
            mainTableView.scrollToRow(at: zeroIndexPath, at: .top, animated: true)
        }
    }
    
    func tappedNotifications() {}
    
    func tappedPost() {}
    
    func tappedDM() {}
    
    func tappedProfile() {}
    
    // MARK: NoteCell Delegate
    
    override func tappedReaction(owner: SecureUser, reactioned: Bool, noteId: String, iconUrl: String?, displayName: String, username: String, hostInstance: String, note: NSAttributedString, hasFile: Bool, hasMarked: Bool, myReaction: String?) {
        if reactioned { // リアクションを取り消す
            guard let myReaction = myReaction else { return }
            viewModel?.updateReaction(targetNoteId: noteId,
                                      reaction: myReaction,
                                      isMyReaction: true,
                                      plus: false,
                                      external: nil,
                                      needReloading: true)
            return
        }
        
        let reactionGen = presentReactionGen(owner: owner,
                                             noteId: noteId,
                                             iconUrl: iconUrl,
                                             displayName: displayName,
                                             username: username,
                                             hostInstance: hostInstance,
                                             note: note,
                                             hasFile: hasFile,
                                             hasMarked: hasMarked,
                                             navigationController: homeViewController?.navigationController)
        
        reactionGen?.selectedEmoji.subscribe(onNext: { emojiModel in
            guard let raw = emojiModel.isDefault ? emojiModel.defaultEmoji : ":" + emojiModel.rawEmoji + ":" else { return }
            self.viewModel?.updateReaction(targetNoteId: noteId,
                                           reaction: raw,
                                           isMyReaction: true,
                                           plus: true,
                                           external: nil,
                                           needReloading: true)
        }).disposed(by: disposeBag)
    }
    
    override func updateMyReaction(targetNoteId: String, rawReaction: String, plus: Bool) {
        viewModel?.updateReaction(targetNoteId: targetNoteId,
                                  reaction: rawReaction,
                                  isMyReaction: true,
                                  plus: plus,
                                  external: nil,
                                  needReloading: false)
    }
    
    override func tappedOthers(note: NoteCell.Model) {
        guard let owner = viewModel?.state.owner else { return }
        // ユーザーをブロック・投稿を通報する
        // 投稿の削除
        note.noteEntity.userId.isMe(owner: owner) { isMe in
            if isMe { self.showOtherMenuForMe(note); return }
            self.showOtherMenuForOthers(note)
        }
    }
    
    /// 他人の投稿に対する...ボタン(三点リーダーボタン)の挙動
    private func showOtherMenuForOthers(_ note: NoteCell.Model) {
        let panelMenu = PanelMenuViewController()
        let menuItems: [PanelMenuViewController.MenuItem] = [.init(title: "ユーザーをブロック", awesomeIcon: "angry", order: 0),
                                                             .init(title: "投稿を通報する", awesomeIcon: "ban", order: 1)]
        
        panelMenu.setupMenu(items: menuItems)
        panelMenu.tapTrigger.asDriver(onErrorDriveWith: Driver.empty()).drive(onNext: { order in // どのメニューがタップされたのか
            guard order >= 0 else { return }
            panelMenu.dismiss(animated: true, completion: nil)
            
            switch order {
            case 0: // Block
                self.showBlockAlert(note)
            case 1: // Report
                self.showReportAlert(note)
            default:
                break
            }
        }).disposed(by: disposeBag)
        
        present(panelMenu, animated: true, completion: nil)
    }
    
    /// 自分の投稿に対する...ボタン(三点リーダーボタン)の挙動
    private func showOtherMenuForMe(_ note: NoteCell.Model) {
        let panelMenu = PanelMenuViewController()
        let menuItems: [PanelMenuViewController.MenuItem] = [.init(title: "投稿を削除する", awesomeIcon: "trash-alt", order: 0)]
        
        panelMenu.setupMenu(items: menuItems)
        panelMenu.tapTrigger.asDriver(onErrorDriveWith: Driver.empty()).drive(onNext: { order in // どのメニューがタップされたのか
            guard order >= 0 else { return }
            panelMenu.dismiss(animated: true, completion: nil)
            
            switch order {
            case 0:
                self.showDeleteAlert(note)
            default:
                break
            }
        }).disposed(by: disposeBag)
        
        present(panelMenu, animated: true, completion: nil)
    }
    
    private func showBlockAlert(_ note: NoteCell.Model) {
        showAlert(title: "ブロック", message: "本当にこのユーザーをブロックしますか？", yesOption: "ブロック") { yes in
            guard yes else { return }
            self.viewModel?.block(userId: note.noteEntity.userId)
        }
    }
    
    private func showReportAlert(_ note: NoteCell.Model) {
        // 投稿を削除する
        // ユーザーをブロック
        showTextAlert(title: "迷惑行為の詳細を記述してください", placeholder: "例: 著作権侵害/不適切な投稿など") { message in
            self.showAlert(title: "通報", message: "本当にこの投稿を通報しますか？", yesOption: "通報") { yes in
                guard yes else { return }
                self.viewModel?.report(message: message, userId: note.noteEntity.userId)
            }
        }
    }
    
    private func showDeleteAlert(_ note: NoteCell.Model) {
        showAlert(title: "削除", message: "本当にこの投稿を削除しますか？", yesOption: "削除") { okay in
            guard let noteId = note.noteEntity.noteId, okay else { return }
            self.viewModel?.deleteMyNote(noteId: noteId)
        }
    }
    
    private func showTextAlert(title: String, placeholder: String, handler: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: "", preferredStyle: .alert)
        let okAction = UIAlertAction(title: "決定", style: .default) { (_: UIAlertAction) in
            guard let textFields = alert.textFields, textFields.count == 1, let text = textFields[0].text else { return }
            if text.isEmpty {
                self.showAlert(title: "エラー", message: "必ず入力してください") { _ in
                    self.showTextAlert(title: title, placeholder: placeholder, handler: handler)
                }
                return
            }
            
            handler(text)
        }
        let cancelAction = UIAlertAction(title: "閉じる", style: .cancel, handler: nil)
        
        alert.addAction(okAction)
        alert.addAction(cancelAction)
        
        alert.addTextField { text in
            text.placeholder = placeholder
        }
        
        present(alert, animated: true, completion: nil)
    }
    
    // MARK: XLPagerTabStrip delegate
    
    func indicatorInfo(for pagerTabStripController: PagerTabStripViewController) -> IndicatorInfo {
        return xlTitle ?? "Home"
    }
}
