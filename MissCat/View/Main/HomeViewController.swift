//
//  HomeViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/16.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Agrume
import AVKit
import MisskeyKit
import PolioPager
import RxCocoa
import RxSwift
import UIKit

// **    方針    **
// 基本的にはMVVMパターンを採用し、View / UIViewControllerの管理はこのHomeViewControllerが行う。
// 上タブ管理はBGで動いている親クラスのPolioPagerが行い、下タブ管理はHomeViewControllerが自前で行う。
// 一時的なキャッシュ管理についてはsingletonのCacheクラスを使用

extension HomeViewController {
    struct Tab {
        var name: String
        var kind: Theme.TabKind
        
        var userId: String?
        var listId: String?
        
        let owner: SecureUser
    }
}

class HomeViewController: PolioPagerViewController, UIGestureRecognizerDelegate {
    private var isXSeries = UIScreen.main.bounds.size.height > 811
    private let footerTabHeight: CGFloat = 55
    private var initialized: Bool = false
    
    // ViewController
    private var notificationsViewController: NotificationsViewController?
    private var detailViewController: UIViewController?
    private var favViewController: MessageListViewController?
    
    private var accountsListViewController: AccountsListViewController?
    
    // Tab
    private lazy var search = self.generateSearchVC()
    private var setViewControllers: [UIViewController] = []
    
    private lazy var navBar: NavBar = NavBar()
    private lazy var footerTab = FooterTabBar(with: disposeBag)
    
    // Flag
    private var hasPreparedViews: Bool = false // NavBar, FooterTabをこのVCのview上に配置したか？
    
    // Status
    private var nowPage: Page = .main {
        willSet(page) {
            previousPage = nowPage
        }
    }
    
    private var previousPage: Page = .main
    private var logined: Bool = false
    private var currentInstance: String = "misskey.io"
    private var io: Bool { return currentInstance == "misskey.io" }
    
    private var viewModel = HomeViewModel()
    private var disposeBag = DisposeBag()
    
    private lazy var tabs: [Tab] = transformTabs()
    
    // MARK: Transform Tabs
    
    private func transformTabs() -> [Tab] {
        guard let tabs = Theme.shared.currentModel?.tab else { return [] }
        
        // Theme.Tab → HomeViewController.Tabへと詰め替える
        let transformed: [Tab] = tabs.compactMap {
            guard let userId = $0.userId ?? Cache.UserDefaults.shared.getCurrentUserId(),
                let owner = Cache.UserDefaults.shared.getUser(userId: userId) else { return nil }
            
            // Homeタブがデフォルト値だったら修正しておく(userRefillが完了すれば、次の起動では正常に表示されるはず)
            if $0.name == "___Home___" {
                return Tab(name: "Home", kind: $0.kind, userId: $0.userId, listId: $0.listId, owner: owner)
            }
            return Tab(name: $0.name, kind: $0.kind, userId: $0.userId, listId: $0.listId, owner: owner)
        }
        
        return transformed
    }
    
    // MARK: PolioPager Overrides
    
    /// 上タブのアイテム
    override func tabItems() -> [TabItem] {
        let colorPattern = Theme.shared.currentModel?.colorPattern
        let items = tabs.map { tab in
            TabItem(title: tab.name,
                    backgroundColor: colorPattern?.ui.base ?? .white,
                    normalColor: colorPattern?.ui.text ?? .black)
        }
        
        return items.count > 0 ? items : [TabItem(title: "")]
    }
    
    /// 上タブのアイテムに対応したViewControllerを返す
    override func viewControllers() -> [UIViewController] {
        setViewControllers = tabs.map { tab in // setされたviewControllerを記憶しておく
            getViewController(type: tab.kind, owner: tab.owner)
        }
        
        if setViewControllers.count == 0 {
            setViewControllers = [UIViewController()]
        }
        
        return [search] + setViewControllers
    }
    
    /// Theme.TabKindからVCを生成
    /// - Parameter type: Theme.TabKind
    private func getViewController(type: Theme.TabKind, owner user: SecureUser) -> UIViewController {
        switch type {
        case .home:
            return generateTimelineVC(type: .Home, of: user)
        case .local:
            // ioの場合はLTLではなくHomeを表示(Appleに怒られた)
            return io ? generateTimelineVC(type: .Home, of: user) : generateTimelineVC(type: .Local, of: user)
        case .social:
            return io ? generateTimelineVC(type: .Home, of: user) : generateTimelineVC(type: .Social, of: user)
        case .global:
            return generateTimelineVC(type: .Global, of: user)
        case .user:
            return .init()
        case .list:
            return .init()
        }
    }
    
    // MARK: Life Cycle
    
    override func viewDidLoad() {
        setupPolioPager()
        bindTheme()
        setTheme()
        
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        if !logined { userAuth() } // アカウントを一つも持っていない場合はログインさせる
        super.viewDidAppear(animated)
        
        navigationController?.delegate = self
        navigationController?.interactivePopGestureRecognizer?.delegate = self
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        
        guard !initialized else { return }
        
        setupFooterTab()
        loadingBanner()
        setTheme()
        initialized = true
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        setupNotificationsVC() // 先にNotificationsVCをロードしておく → 通知のロードを裏で行う
        setupFavVC()
        setupAccountListVC()
        setupNavTab()
    }
    
    /// Viewを総relaunchします。
    /// アカウントの切り替えやデザインの変更時に用いる。
    /// - Parameter startingPage: どのpageがrelaunch後、最初に表示されるか
    func relaunchView(start startingPage: Page = .profile) {
        // main
        tabs = transformTabs() // タブ情報を更新する
        reloadPager()
        
        // notif
        notificationsViewController?.view.removeFromSuperview()
        notificationsViewController?.removeFromParent()
        notificationsViewController = nil
        setupNotificationsVC()
        
        // fav
        favViewController?.view.removeFromSuperview()
        favViewController?.removeFromParent()
        favViewController = nil
        setupFavVC()
        
        // profile
//        myProfileViewController?.view.removeFromSuperview()
//        myProfileViewController?.removeFromParent()
//        myProfileViewController = nil
        
        accountsListViewController?.view.removeFromSuperview()
        accountsListViewController?.removeFromParent()
        accountsListViewController = nil
        
        nowPage = .main
        switch startingPage {
        case .main:
            nowPage = .profile // fake
            emulateFooterTabTap(tab: .home)
        case .notifications:
            emulateFooterTabTap(tab: .notifications)
        case .profile:
            emulateFooterTabTap(tab: .profile)
        case .messages:
            emulateFooterTabTap(tab: .messages)
        }
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    // たまにnavigationControllerが機能しなくなってフリーズするため、フリーズしないように
    // 参考→　https://stackoverflow.com/a/36637556
    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        if navigationController.viewControllers.count > 1 {
            self.navigationController?.interactivePopGestureRecognizer?.delegate = self
            navigationController.interactivePopGestureRecognizer?.isEnabled = true
        } else {
            self.navigationController?.interactivePopGestureRecognizer?.delegate = nil
            navigationController.interactivePopGestureRecognizer?.isEnabled = false
        }
    }
    
    // MARK: Design
    
    private func setupPolioPager() {
        needBorder = true
        selectedBarHeight = 2
        selectedBar.layer.cornerRadius = 2
        selectedBarMargins.lower += 1
        sectionInset = .init(top: 0, left: 20, bottom: 0, right: 5)
        navBar.isHidden = true
        
        if !isXSeries {
            selectedBarMargins.upper += 3
            selectedBarMargins.lower += 1
            sectionInset = .init(top: 2, left: 10, bottom: 0, right: 5)
        }
    }
    
    private func bindTheme() {
        let theme = Theme.shared.theme
        var currentTheme = Theme.shared.currentModel
        
        theme.map { $0 }.subscribe(onNext: { theme in
            self.searchIconColor = theme.colorMode == .light ? .black : .white
            
            // タブ情報が更新されている場合のみタブをリロード
            if let oldTheme = currentTheme {
                if !theme.hasEqualTabs(to: oldTheme) {
                    self.tabs = self.transformTabs() // タブ情報を更新する
                    self.reloadPager()
                }
            } else {
                self.tabs = self.transformTabs() // タブ情報を更新する
                self.reloadPager()
            }
            
            currentTheme = theme // 更新しておく
        }).disposed(by: disposeBag)
        
        theme.map { UIColor(hex: $0.mainColorHex) }.bind(to: selectedBar.rx.backgroundColor).disposed(by: disposeBag)
        theme.map { $0.colorPattern.ui.base }.subscribe(onNext: { baseColor in
            self.changeBackground(to: baseColor)
            self.setNeedsStatusBarAppearanceUpdate() // ステータスバーの文字色を変更
        }).disposed(by: disposeBag)
    }
    
    private func setTheme() {
        guard let theme = Theme.shared.currentModel else { return }
        
        let mainColorHex = theme.mainColorHex
        let mainColor = UIColor(hex: mainColorHex)
        
        // mainColor
        view.window?.tintColor = mainColor
        selectedBar.backgroundColor = mainColor
        
        let colorPattern = theme.colorPattern
        
        // colorPattern
        changeBackground(to: colorPattern.ui.base)
        borderColor = colorPattern.ui.sub2
        searchIconColor = theme.colorMode == .light ? .black : .white // 検索アイコンの色を変更
        UINavigationBar.changeColor(back: colorPattern.ui.base, text: colorPattern.ui.text) // ナビゲーションバーの色を変更
        
        setNeedsStatusBarAppearanceUpdate() // ステータスバーの文字色を変更
    }
    
    private func changeBackground(to color: UIColor) {
        view.backgroundColor = color
        collectionView.backgroundColor = color
        tabBackgroundColor = color
    }
    
    /// ステータスバーの文字色
    override var preferredStatusBarStyle: UIStatusBarStyle {
        let currentColorMode = Theme.shared.currentModel?.colorMode ?? .light
        return currentColorMode == .light ? UIStatusBarStyle.default : UIStatusBarStyle.lightContent
    }
    
    // MARK: Auth
    
    private func userAuth() {
        guard let currentUser = Cache.UserDefaults.shared.getCurrentUser(),
            let apiKey = currentUser.apiKey,
            !apiKey.isEmpty else {
            showStartingViewController() // ApiKeyが確認できない場合はStartViewControllerへ
            return
        }
        
//        MisskeyKit.changeInstance(instance: currentUser.instance)
//        MisskeyKit.auth.setAPIKey(apiKey)
        
        logined = true
        currentInstance = currentUser.instance
    }
    
    private func showStartingViewController() {
        guard let startViewController = getViewController(name: "start") as? StartViewController else { return }
        
        startViewController.reloadTrigger.subscribe(onNext: {
            self.relaunchView(start: .main)
        }).disposed(by: disposeBag)
        
        let navigationController = UINavigationController(rootViewController: startViewController)
        presentOnFullScreen(navigationController, animated: true, completion: nil)
    }
    
    // MARK: Setup Tab
    
    private func setupFooterTab() {
        footerTab.frame = getFooterTabSize(height: footerTabHeight)
        view.addSubview(footerTab)
        
        footerTab.delegate = self
        footerTab.selected = .home
    }
    
    private func setupNavTab() {
        if !hasPreparedViews {
            view.addSubview(navBar)
            hasPreparedViews = true
        }
        
        navBar.delegate = self
        navBar.frame = CGRect(x: 0,
                              y: 0,
                              width: view.frame.width,
                              height: pageView.frame.origin.y)
    }
    
    // MARK: Setup Initial View
    
    private func setupNotificationsVC() {
        if notificationsViewController == nil {
            guard let storyboard = self.storyboard, let notificationsViewController = storyboard.instantiateViewController(withIdentifier: "notifications") as? NotificationsViewController else { return }
            notificationsViewController.homeViewController = self
            self.notificationsViewController = notificationsViewController
            
            navBar.barTitle = "Notifications"
            navBar.setButton(style: .None, rightFont: nil, leftFont: nil)
        }
        
        notificationsViewController!.view.frame = getDisplayRect()
    }
    
    private func setupFavVC() {
        if favViewController == nil {
            guard let storyboard = self.storyboard,
                let favViewController = storyboard.instantiateViewController(withIdentifier: "messages") as? MessageListViewController
            else { return }
            
            favViewController.homeViewController = self
            self.favViewController = favViewController
            
            navBar.barTitle = "Chat"
//            navBar.setButton(style: .Right, rightText: "plus", rightFont: UIFont.awesomeSolid(fontSize: 11))
            navBar.setButton(style: .None, rightText: nil, leftText: nil)
        }
        
        favViewController!.view.frame = getDisplayRect()
    }
    
    private func setupAccountListVC() {
        if accountsListViewController == nil {
            guard let storyboard = self.storyboard,
                let accountsListViewController = storyboard.instantiateViewController(withIdentifier: "accounts-list") as? AccountsListViewController else { return }
            
            accountsListViewController.homeViewController = self
            accountsListViewController.view.layoutIfNeeded()
            
            self.accountsListViewController = accountsListViewController
        }
        
        accountsListViewController!.view.frame = getDisplayRect(needNavBar: true)
    }
    
    // MARK: Pages
    
    private func showPostDetailView(item: NoteCell.Model) {
        guard let storyboard = self.storyboard else { return }
        guard let detailViewController = storyboard.instantiateViewController(withIdentifier: "post-detail") as? PostDetailViewController else { return }
        
        detailViewController.view.frame = getDisplayRect()
        detailViewController.mainItem = item
        detailViewController.homeViewController = self
        
        navigationController?.pushViewController(detailViewController, animated: true)
        
        view.bringSubviewToFront(navBar)
        view.bringSubviewToFront(footerTab)
        
        self.detailViewController = detailViewController
    }
    
    private func showProfileView(userId: String, owner: SecureUser) {
        guard let storyboard = self.storyboard,
            let profileViewController = storyboard.instantiateViewController(withIdentifier: "profile") as? ProfileViewController else { return }
        
        profileViewController.setUserId(userId, owner: owner)
        profileViewController.view.frame = getDisplayRect(needNavBar: false)
        profileViewController.homeViewController = self
        
        navigationController?.pushViewController(profileViewController, animated: true)
    }
    
    // MARK: Utilities
    
    private func getViewController(name: String) -> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyboard.instantiateViewController(withIdentifier: name)
        
        guard let timelineViewController = viewController as? TimelineViewController else { return viewController }
        timelineViewController.homeViewController = self
        
        return timelineViewController
    }
    
    private func getDisplayRect(needNavBar: Bool = true) -> CGRect {
        let pageHeight = pageView.frame.height - (view.frame.height - footerTab.frame.origin.y)
        let navBarHeight = pageView.frame.origin.y
        
        let y = needNavBar ? pageView.frame.origin.y : 0
        let height = pageHeight + (needNavBar ? 0 : navBarHeight)
        
        return CGRect(x: 0,
                      y: y,
                      width: view.frame.width,
                      height: height)
    }
    
    private func backNavBarStatus() {
        switch previousPage {
        case .main:
            tappedHome()
            
        case .notifications:
            tappedNotifications()
            
        default:
            return
        }
    }
    
    private func generateSearchVC() -> SearchViewController {
        guard let viewController = getViewController(name: "search") as? SearchViewController
        else { fatalError("Internal Error.") }
        
        viewController.homeViewController = self
        viewController.view.backgroundColor = .clear
        return viewController
    }
    
    private func generateTimelineVC(type: TimelineType, of user: SecureUser) -> TimelineViewController {
        guard let viewController = getViewController(name: "timeline") as? TimelineViewController
        else { fatalError("Internal Error.") }
        
        viewController.setup(owner: user, type: type)
        viewController.view.backgroundColor = .clear
        return viewController
    }
    
    private func hideView(without type: Page) {
        navBar.isHidden = true
        
        if type != .notifications {
            notificationsViewController?.removeFromParent()
            notificationsViewController?.view.removeFromSuperview()
        }
        
        if type != .profile {
            accountsListViewController?.removeFromParent()
            accountsListViewController?.view.removeFromSuperview()
        }
        
        if type != .messages {
            favViewController?.removeFromParent()
            favViewController?.view.removeFromSuperview()
        }
    }
    
    // MARK: Notitifcation
    
    func showNotificationBanner(with contents: NotificationModel, owner: SecureUser) {
        DispatchQueue.main.async {
            let banner = NotificationBanner(with: contents, owner: owner)
            
            banner.translatesAutoresizingMaskIntoConstraints = false
            banner.layer.cornerRadius = 8
            self.view.addSubview(banner)
            
            banner.setAutoLayout(on: self.view, widthScale: 0.9, height: self.footerTabHeight * 2, bottom: self.footerTabHeight + 10)
            banner.rxTap.subscribe(onNext: { _ in
                guard let notificationId = contents.id else { return }
                self.openNotification(notificationId, owner: owner)
                banner.disappear()
            }).disposed(by: self.disposeBag)
            
            self.view.bringSubviewToFront(banner)
        }
    }
    
    func showNanoBanner(icon: NanoNotificationBanner.IconType, notification: String) {
        DispatchQueue.main.async {
            let bannerWidth = self.view.frame.width / 3
            
            let frame = CGRect(x: self.view.frame.width - bannerWidth - 10,
                               y: self.footerTab.frame.origin.y - 30,
                               width: bannerWidth,
                               height: 30)
            
            let notificationBanner = NanoNotificationBanner(frame: frame, icon: icon, notification: notification)
            self.view.addSubview(notificationBanner)
            self.view.bringSubviewToFront(notificationBanner)
        }
    }
    
    private func openNotification(_ notificationId: String, owner: SecureUser) {
        navBar.changeUser(to: owner) // ユーザーを変更しておく
        emulateFooterTabTap(tab: .notifications)
    }
}

// MARK: NoteCell Delegate

extension HomeViewController: NoteCellDelegate {
    func tappedReply(note: NoteCell.Model) {
        openPost(item: note, type: .Reply)
    }
    
    func tappedRenote(note: NoteCell.Model) {
        let panelMenu = PanelMenuViewController()
        let menuItems: [PanelMenuViewController.MenuItem] = [.init(title: "Renote", awesomeIcon: "retweet", order: 0),
                                                             .init(title: "引用Renote", awesomeIcon: "quote-right", order: 1)]
        
        panelMenu.setupMenu(items: menuItems)
        panelMenu.tapTrigger.asDriver(onErrorDriveWith: Driver.empty()).drive(onNext: { order in // どのメニューがタップされたのか
            guard order >= 0 else { return }
            panelMenu.dismiss(animated: true, completion: nil)
            
            switch order {
            case 0: // RN
                guard let noteId = note.noteEntity.noteId, let owner = note.owner else { return }
                self.viewModel.renote(noteId: noteId, owner: owner)
            case 1: // 引用RN
                self.openPost(item: note, type: .CommentRenote)
            default:
                break
            }
       }).disposed(by: disposeBag)
        
        present(panelMenu, animated: true, completion: nil)
    }
    
    func tappedReaction(owner: SecureUser, reactioned: Bool, noteId: String, iconUrl: String?, displayName: String, username: String, hostInstance: String, note: NSAttributedString, hasFile: Bool, hasMarked: Bool, myReaction: String?) {}
    
    func tappedOthers(note: NoteCell.Model) {}
    
    func move2PostDetail(item: NoteCell.Model) {
        tappedCell(item: item)
    }
    
    func tappedLink(text: String, owner: SecureUser) {
        let (linkType, value) = text.analyzeHyperLink()
        
        switch linkType {
        case .url:
            openLink(url: value)
        case .user:
            openUserPage(username: value, owner: owner)
        case .hashtag:
            searchHashtag(tag: value)
        default:
            break
        }
    }
    
    func updateMyReaction(targetNoteId: String, rawReaction: String, plus: Bool) {}
    
    func vote(choice: [Int], to noteId: String, owner: SecureUser) {
        viewModel.vote(choice: choice, to: noteId, owner: owner)
    }
    
    func showImage(_ urls: [URL], start startIndex: Int) {
        viewImage(urls: urls, startIndex: startIndex, disposeBag: disposeBag)
    }
    
    func playVideo(url: String) {
        guard let url = URL(string: url) else { return }
        let videoPlayer = AVPlayer(url: url)
        let playerController = AVPlayerViewController()
        playerController.player = videoPlayer
        
        present(playerController, animated: true, completion: {
            videoPlayer.play()
       })
    }
}

// MARK: FooterTabBar Delegate

extension HomeViewController: FooterTabBarDelegate {
    func emulateFooterTabTap(tab: TabKind) {
        footerTab.selected = tab
        switch tab {
        case .home:
            tappedHome()
            
        case .notifications:
            tappedNotifications()
            
        case .profile:
            tappedProfile()
            
        case .messages:
            tappedDM()
        }
    }
    
    func tappedHome() {
        if nowPage != .main {
            nowPage = .main
            DispatchQueue.main.async { self.hideView(without: .main) }
        } else {
            // PolioPagerが管理しているvcにタップイベントを伝達させる
            setViewControllers.compactMap { $0 as? FooterTabBarDelegate }.forEach {
                $0.tappedHome()
            }
        }
    }
    
    func tappedNotifications() {
        guard let notificationsViewController = notificationsViewController else { return }
        
        if nowPage == .notifications {
            guard let notificationsView = notificationsViewController as? FooterTabBarDelegate else { return }
            notificationsView.tappedNotifications()
        } else {
            DispatchQueue.main.async {
                self.hideView(without: .notifications)
                self.showNotificationsView()
            }
        }
    }
    
    func tappedPost() {
        guard let postViewController = storyboard?.instantiateViewController(withIdentifier: "post") as? PostViewController,
            let owner = Cache.UserDefaults.shared.getCurrentUser() else { return }
        
        postViewController.setup(owner: owner)
        presentOnFullScreen(postViewController, animated: true, completion: nil)
    }
    
    func tappedDM() {
        if nowPage != .messages {
            DispatchQueue.main.async {
                self.hideView(without: .messages)
                self.showFavView()
            }
        }
    }
    
    func tappedProfile() {
        guard nowPage != .profile else { return }
        
        DispatchQueue.main.async {
            self.hideView(without: .profile)
            self.showAccountListView()
            // TODO: ここでアカウント選択画面を出す
        }
    }
    
    // MARK: FooterTab's Pages
    
    // 下タブに対応するViewControllerを操作するメソッド群
    
    private func showNotificationsView() {
        guard let notificationsViewController = notificationsViewController else { return }
        
        showNavBar(title: "Notifications", page: .notifications)
        addChild(notificationsViewController)
        view.addSubview(notificationsViewController.view)
        view.bringSubviewToFront(navBar)
        view.bringSubviewToFront(footerTab)
    }
    
    func showFavView() {
        guard let favViewController = favViewController else { return }
        
        showNavBar(title: "Chat", page: .messages)
        addChild(favViewController)
        view.addSubview(favViewController.view)
        view.bringSubviewToFront(navBar)
        view.bringSubviewToFront(footerTab)
    }
    
    private func showAccountListView() {
        guard let accountsListViewController = accountsListViewController else { return }
        
        showNavBar(title: "Accounts", page: .profile, style: .Right, needIcon: false, rightText: "cog")
        addChild(accountsListViewController)
        view.addSubview(accountsListViewController.view)
        view.bringSubviewToFront(navBar)
        view.bringSubviewToFront(footerTab)
    }
    
    private func showNavBar(title: String, page: Page, style: NavBar.Button = .None, needIcon: Bool = true, rightText: String? = nil, rightFont: UIFont? = nil) {
        navBar.isHidden = false
        navBar.barTitle = title
        navBar.setButton(style: style,
                         needIcon: needIcon,
                         rightText: rightText,
                         leftText: nil,
                         rightFont: rightFont ?? UIFont.awesomeSolid(fontSize: 16))
        
        nowPage = page
    }
}

extension HomeViewController: NavBarDelegate {
    func changeUser(_ user: SecureUser) {
        favViewController?.changeUser(user)
        notificationsViewController?.changeUser(user)
    }
    
    func tappedRightNavButton() {
        openSettings()
    }
    
    func showAccountMenu(sourceRect: CGRect) -> Observable<SecureUser>? {
        return presentAccountsDropdownMenu(sourceRect: sourceRect)
    }
}

// MARK: Timeline Delegate

extension HomeViewController: TimelineDelegate {
    func tappedCell(item: NoteCell.Model) {
        showPostDetailView(item: item)
    }
    
    func move2Profile(userId: String, owner: SecureUser) {
        showProfileView(userId: userId, owner: owner)
    }
    
    func openUserPage(username: String, owner: SecureUser) {
        // usernameから真のusernameとhostを切り離す
        let decomp = username.components(separatedBy: "@").filter { $0 != "" }
        
        var _username = ""
        var host = ""
        if decomp.count == 1 {
            host = ""
            _username = decomp[0]
        } else if decomp.count == 2 {
            host = decomp[1]
            _username = decomp[0]
        } else { return }
        
        let misskey = MisskeyKit(from: owner)
        misskey?.users.showUser(username: _username, host: host) { user, error in
            guard error == nil, let user = user else { return }
            DispatchQueue.main.async {
                self.showProfileView(userId: user.id, owner: owner)
            }
        }
    }
    
    func searchHashtag(tag: String) {
        moveTo(index: 0)
        search.searchNote(with: tag)
    }
    
    func openSettings() {
        guard let storyboard = self.storyboard,
            let settingsViewController = storyboard.instantiateViewController(withIdentifier: "settings")
            as? SettingsViewController else { return }
        
        settingsViewController.homeViewController = self
        navigationController?.pushViewController(settingsViewController, animated: true)
    }
    
    func openPost(item: NoteCell.Model, type: PostViewController.PostType) {
        guard let postViewController = storyboard?.instantiateViewController(withIdentifier: "post") as? PostViewController,
            let owner = item.owner else { return }
        
        postViewController.setup(owner: owner, note: item, type: type)
        presentOnFullScreen(postViewController, animated: true, completion: nil)
    }
    
    func successInitialLoading(_ success: Bool) {
        guard !success else { return }
        
        showNanoBanner(icon: .Failed, notification: "投稿の取得に失敗しました")
    }
    
    func changedStreamState(success: Bool) {
        guard !success else { return }
        //        showNotificationBanner(icon: .Failed, notification: "Streamingへ再接続します")
    }
    
    func loadingBanner() {
        showNanoBanner(icon: .Loading, notification: "ロード中...")
    }
}

extension HomeViewController {
    enum Page {
        // FooterTab
        case main
        case notifications
        case profile
        case messages
    }
}
