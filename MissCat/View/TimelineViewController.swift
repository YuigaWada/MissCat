//
//  TimelineViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/07.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit
import MisskeyKit
import RxSwift
import RxDataSources
import SafariServices
import FloatingPanel
import XLPagerTabStrip

public protocol TimelineDelegate {
    func tappedCell(item: NoteCell.Model)
    func move2Profile(userId: String)
}

typealias NotesDataSource = RxTableViewSectionedAnimatedDataSource<NoteCell.Section>
class TimelineViewController: UIViewController, UITableViewDelegate, FooterTabBarDelegate, NoteCellDelegate,IndicatorInfoProvider {
    @IBOutlet weak var mainTableView: UITableView!
    @IBOutlet weak var bottomConstraint: NSLayoutConstraint!
    
    private let disposeBag = DisposeBag()
    private lazy var refreshControl = UIRefreshControl()
    
    private var viewModel: TimelineViewModel?
    private var loadCompleted: Bool = true
    private var cellHeightCache: [String: CGFloat] = [:] //String → identifier
    private var withNavBar: Bool = true
    private var scrollable: Bool = true
    private var streamConnecting: Bool = false
    
    public var homeViewController: TimelineDelegate?
    public var xlTitle: IndicatorInfo? // XLPagerTabStripで用いるtitle
    
    
    //MARK: Life Cycle
    public func setup(type: TimelineType,
                      includeReplies: Bool? = nil,
                      onlyFiles: Bool? = nil,
                      userId: String? = nil,
                      listId: String? = nil,
                      withNavBar: Bool = true,
                      scrollable: Bool = true,
                      xlTitle: IndicatorInfo? = nil) {
        self.viewModel = .init(type: type,
                               includeReplies: includeReplies,
                               onlyFiles: onlyFiles,
                               userId: userId,
                               listId: listId,
                               disposeBag: disposeBag)
        
        self.streamConnecting = type.needsStreaming
        self.xlTitle = xlTitle
        self.withNavBar = withNavBar
        self.scrollable = scrollable
    }
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.setupTableView()
        self.setupPullGesture()
        if viewModel == nil {
            self.setup(type: .Home)
        }
        
        viewModel!.dataSource = self.setupDataSource() // viewModelの中身は保証されているので強制アンラップでOK
        self.binding(dataSource: viewModel!.dataSource)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.mainTableView.isScrollEnabled = self.scrollable
        if let bottomConstraint = bottomConstraint {
            bottomConstraint.isActive = withNavBar
        }
    }
    
    
    
    
    //MARK: Setup TableView
    private func setupTableView() {
        self.mainTableView.register(UINib(nibName: "NoteCell", bundle: nil), forCellReuseIdentifier: "NoteCell")
        //        self.mainTableView.register(UINib(nibName: "ReactionGenCell", bundle: nil), forCellReuseIdentifier: "ReactionGenCell")
        self.mainTableView.register(UINib(nibName: "RenoteeCell", bundle: nil), forCellReuseIdentifier: "RenoteeCell")
        
        self.mainTableView.rx.setDelegate(self).disposed(by: disposeBag)
    }
    
    
    private func setupDataSource()-> NotesDataSource {
        let dataSource = NotesDataSource(
            animationConfiguration: AnimationConfiguration(insertAnimation: .fade, reloadAnimation: .none, deleteAnimation: .fade),
            configureCell: { dataSource, tableView, indexPath, item in
                return self.setupCell(dataSource,self.mainTableView,indexPath)
        })
        
        
        return dataSource
    }
    
    private func binding(dataSource: NotesDataSource?) {
        guard let viewModel = viewModel, let dataSource = dataSource else { return }
        
        viewModel.notes
            .bind(to: self.mainTableView.rx.items(dataSource: dataSource))
            .disposed(by: disposeBag)
        
        viewModel.forceUpdateIndex.subscribe(onNext: updateForcibly).disposed(by: disposeBag)
    }
    
    
    private func setupPullGesture() {
        self.refreshControl.attributedTitle = NSAttributedString(string: "Refresh...")
        self.refreshControl.addTarget(self, action: #selector(refreshTableView(_:)), for: UIControl.Event.valueChanged)
        
        if !self.streamConnecting {
            self.mainTableView.addSubview(refreshControl) // ストリーミングでないときだけ
        }
    }
    
    @objc func refreshTableView(_ sender: Any) {
        guard let viewModel = viewModel else { return }
        
        viewModel.loadUntilNotes(){
            DispatchQueue.main.async { self.refreshControl.endRefreshing() }
        }
    }
    
    
    
    //MARK: Setup Cell
    private func setupCell(_ dataSource: TableViewSectionedDataSource<NoteCell.Section>, _ tableView: UITableView, _ indexPath: IndexPath)-> UITableViewCell {
        guard let viewModel = viewModel else { fatalError("Internal Error.") }
        
        let index = indexPath.row
        let item = viewModel.cellsModel[index]
        
        //View側で  NoteCell / RenoteeCellを区別する
        //        if let baseNoteId = item.baseNoteId, item.isReactionGenCell {
        //            guard let reactionGenCell = tableView.dequeueReusableCell(withIdentifier: "ReactionGenCell", for: indexPath) as? ReactionGenCell
        //                else { return ReactionGenCell() }
        //
        //            reactionGenCell.setTargetNoteId(item.baseNoteId)
        //            viewModel.resetReactionGenCell(baseNoteId: baseNoteId) //すでに表示してあるReactionGenCellを消す
        //            return reactionGenCell
        //        }
        if item.isRenoteeCell {
            guard let renoteeCell = tableView.dequeueReusableCell(withIdentifier: "RenoteeCell", for: indexPath) as? RenoteeCell
                else { return RenoteeCell() }
            
            renoteeCell.setRenotee(item.renotee ?? "")
            //            renoteeCell.frame = CGRect(x: renoteeCell.frame.origin.x,y: renoteeCell.frame.origin.y,width: renoteeCell.frame.width,height: 16)
            return renoteeCell
        }
        
        
        
        //通常のcellをつくる
        guard let itemCell = tableView.dequeueReusableCell(withIdentifier: "NoteCell", for: indexPath) as? NoteCell else {fatalError("Internal Error.")}
        
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
    
    
    
    
    //MARK: TableView Delegate
    
    //tableViewの負担を軽減するようキャッシュを活用
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let viewModel = viewModel else { return UITableView.automaticDimension }
        
        let index = indexPath.row
        let id = viewModel.cellsModel[index].identity
        
        guard let height = self.cellHeightCache[id] else { return UITableView.automaticDimension }
        return height
    }
    //セル選択後すぐに選択をキャンセルする & ReactionGenCellを消す
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let viewModel = viewModel else { return }
        
        let index = indexPath.row
        
        self.showDetailView(item: viewModel.cellsModel[index])
        tableView.deselectRow(at: indexPath as IndexPath, animated: true)
        
        if viewModel.isReactionGenCell(index: indexPath.row) {
            viewModel.resetReactionGenCell(allClear: true)
        }
        
    }
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let viewModel = viewModel else { return }
        
        let index = indexPath.row
        let id = viewModel.cellsModel[index].identity
        
        //再計算しないでいいようにセルの高さをキャッシュ
        if self.cellHeightCache.keys.contains(id) != true {
            self.cellHeightCache[id] = cell.frame.height
        }
        
        
        //下位20cellsでセル更新
        guard self.loadCompleted, viewModel.cellCount - indexPath.row < 10 else { return }
        
        
        print("loadUntilNotes...")
        self.loadCompleted = false
        viewModel.loadUntilNotes() {
            self.loadCompleted = true //セル更新最中に多重更新されないように
        }
    }
    
    
    //MARK: Utilities
    
    //強制的にセルを更新する
    private func updateForcibly(index: Int) {
        let row = IndexPath(row: index, section: 0)
        DispatchQueue.main.async { self.mainTableView.reloadRows(at: [row], with: .none) }
    }
    
    private func presentReactionGen(noteId: String, iconUrl: String?, displayName: String, username: String, note: NSAttributedString, hasFile: Bool, hasMarked: Bool) {
        guard let reactionGen = self.getViewController(name: "reaction-gen") as? ReactionGenViewController else { return }
        
        self.presentWithSemiModal(reactionGen, animated: true, completion: nil)
        
        reactionGen.setTargetNote(noteId: noteId,
                                  iconUrl: iconUrl,
                                  displayName: displayName,
                                  username: username,
                                  note: note,
                                  hasFile: hasFile,
                                  hasMarked: hasMarked)
    }
    
    private func getViewController(name: String)-> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyboard.instantiateViewController(withIdentifier: name)
        
        return viewController
    }
    
    //MARK: FooterTabBar Delegate
    func tappedHome() {
        self.mainTableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
    }
    
    func tappedNotifications() {
        
    }
    
    func tappedPost() {
        
    }
    
    func tappedFav() {
        
    }
    
    func tappedProfile() {
        
    }
    
    //MARK: NoteCell Delegate
    func tappedReply() {
        
    }
    
    func tappedRenote() {
        
    }
    
    func tappedReaction(noteId: String, iconUrl: String?, displayName: String, username: String, note: NSAttributedString, hasFile: Bool, hasMarked: Bool) {
        self.presentReactionGen(noteId: noteId, iconUrl: iconUrl, displayName: displayName, username: username, note: note, hasFile: hasFile, hasMarked: hasMarked)
    }
    
    func tappedOthers() {
        
    }
    
    func tappedLink(text: String) {
        guard let viewModel = viewModel else { return }
        
        let (linkType, value) = viewModel.analyzeHyperLink(text)
        
        switch linkType {
        case "URL":
            self.openLink(url: value)
        case "User":
            break
        default:
            break
        }
        
    }
    
    func move2Profile(userId: String) {
        guard let homeViewController = self.homeViewController else { return }
        homeViewController.move2Profile(userId: userId)
    }
    
    
    
    private func openLink(url: String) {
        guard let url = URL(string: url), let rootVC = UIApplication.shared.windows[0].rootViewController else { return }
        let safari = SFSafariViewController(url: url)
        
        // i dont know why but it seems that we must launch a safari VC from the root VC.
        rootVC.present(safari, animated: true, completion: nil)
    }
    
    
    //MARK: XLPagerTabStrip delegate
    func indicatorInfo(for pagerTabStripController: PagerTabStripViewController) -> IndicatorInfo {
        return xlTitle ?? "Home"
    }
    
    
}
