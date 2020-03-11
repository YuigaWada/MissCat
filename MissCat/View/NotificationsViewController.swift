//
//  NotificationsViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/24.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxDataSources
import RxSwift
import UIKit

public typealias NotificationDataSource = RxTableViewSectionedAnimatedDataSource<NotificationCell.Section>
public class NotificationsViewController: UIViewController, UITableViewDelegate, FooterTabBarDelegate, NoteCellDelegate {
    @IBOutlet weak var mainTableView: UITableView!
    
    private var viewModel: NotificationsViewModel?
    private let disposeBag = DisposeBag()
    private var loadCompleted: Bool = true
    private var cellHeightCache: [String: CGFloat] = [:] // String → identifier
    
    public var homeViewController: TimelineDelegate?
    
    // MARK: Life Cycle
    
    public override func loadView() {
        super.loadView()
        setupTableView()
        
        self.viewModel = .init(disposeBag: disposeBag)
        
        guard let viewModel = viewModel else { return }
        viewModel.dataSource = setupDataSource()
        binding(dataSource: viewModel.dataSource)
    }
    
    // MARK: Setup TableView
    
    private func setupTableView() {
        mainTableView.register(UINib(nibName: "NotificationCell", bundle: nil), forCellReuseIdentifier: "NotificationCell")
        mainTableView.register(UINib(nibName: "NoteCell", bundle: nil), forCellReuseIdentifier: "NoteCell")
        
        mainTableView.rx.setDelegate(self).disposed(by: disposeBag)
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
        
        viewModel.notes
            .bind(to: mainTableView.rx.items(dataSource: dataSource))
            .disposed(by: disposeBag)
    }
    
    // MARK: Setup Cell
    
    private func setupCell(_ dataSource: TableViewSectionedDataSource<NotificationCell.Section>, _ tableView: UITableView, _ indexPath: IndexPath) -> UITableViewCell {
        guard let viewModel = viewModel else { return UITableViewCell() }
        
        let index = indexPath.row
        let item = viewModel.cellsModel[index]
        
        if item.type == .reply || item.type == .mention {
            guard let noteCell = tableView.dequeueReusableCell(withIdentifier: "NoteCell", for: indexPath) as? NoteCell, let replyNote = item.replyNote
            else { return NoteCell() }
            
            let shapedCell = noteCell.transform(with: .init(item: replyNote))
            shapedCell.delegate = self
            
            return shapedCell
        } else if item.type == .reaction || item.type == .renote {
            guard let notificationCell = tableView.dequeueReusableCell(withIdentifier: "NotificationCell", for: indexPath) as? NotificationCell
            else { return NotificationCell() }
            
            notificationCell.delegate = self
            return notificationCell.shapeCell(item: item)
        }
        
        return UITableViewCell()
    }
    
    // tableViewの負担を軽減するようキャッシュを活用
    public func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let viewModel = viewModel else { return UITableView.automaticDimension }
        
        let index = indexPath.row
        let id = viewModel.cellsModel[index].identity
        
        guard let height = cellHeightCache[id] else { return UITableView.automaticDimension }
        return height
    }
    
    // セル選択後すぐに選択をキャンセルする
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath as IndexPath, animated: true)
    }
    
    public func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
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
    
    // MARK: Delegate
    
    public func tappedNotifications() {
        mainTableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
    }
    
    public func tappedHome() {}
    
    public func tappedPost() {}
    
    public func tappedFav() {}
    
    public func tappedProfile() {}
    
    // MARK: NoteCellDelegate
    
    public func tappedReply() {}
    
    public func tappedRenote() {}
    
    public func tappedReaction(noteId: String, iconUrl: String?, displayName: String, username: String, note: NSAttributedString, hasFile: Bool, hasMarked: Bool) {
        presentReactionGen(noteId: noteId, iconUrl: iconUrl, displayName: displayName, username: username, note: note, hasFile: hasFile, hasMarked: hasMarked)
    }
    
    public func tappedOthers() {}
    
    public func tappedLink(text: String) {
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
    
    public func move2Profile(userId: String) {
        guard let homeViewController = self.homeViewController else { return }
        homeViewController.move2Profile(userId: userId)
    }
    
    public func vote(choice: Int, to noteId: String) {}
    
    public func playVideo(url: String) {}
    
    public func move2PostDetail(item: NoteCell.Model) {
        homeViewController?.tappedCell(item: item)
    }
}
