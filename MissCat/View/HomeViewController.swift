//
//  HomeViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/16.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import PolioPager
import UIKit

// **    方針    **
// 基本的にはMVVMパターンを採用し、View / UIViewControllerの管理はこのHomeViewControllerが行う。
// 上タブ管理はBGで動いている親クラスのPolioPagerが行い、下タブ管理はHomeViewControllerが自前で行う。

// 各Timeline: それぞれのtimelineの情報をそれぞれのview上で行う / Streamingは"hogehoge timeline"チャンネルを通す。
//  | ← 上タブ管理
// HomeViewController: 上下のタブを管理し、すべてのViewはこのvc上で動かす ＝ 画面遷移はすべてこのVCに委譲する
//  | ← 通知のバインディング
// NotificationsViewController: 通知を管理 / Streamingは"main"チャンネルを通す / UserDefaultsで最新通知のidを永続化

// (OOPの対極的存在である)一時的なキャッシュ管理についてはsingletonのCacheクラスを使用。

public class HomeViewController: PolioPagerViewController, FooterTabBarDelegate, TimelineDelegate, NavBarDelegate, UIGestureRecognizerDelegate, UINavigationControllerDelegate {
    private var isXSeries = UIScreen.main.bounds.size.height > 811
    private let footerTabHeight: CGFloat = 55
    private var initialized: Bool = false
    
    // ViewController
    private var notificationsViewController: UIViewController?
    private var detailViewController: UIViewController?
    
    private var myProfileViewController: ProfileViewController?
    private var currentProfileViewController: ProfileViewController?
    
    private lazy var search = self.getViewController(name: "search")
    private lazy var home = self.generateTimelineVC(type: .Home)
    private lazy var local = self.generateTimelineVC(type: .Local)
    private lazy var global = self.generateTimelineVC(type: .Global)
    
    // Tab
    private lazy var navBar: NavBar = NavBar()
    private lazy var footerTab = FooterTabBar()
    
    // Flag
    private var hasPreparedViews: Bool = false // NavBar, FooterTabをこのVCのview上に配置したか？
    
    // Status
    private var nowPage: Page = .Main {
        willSet(page) {
            previousPage = nowPage
        }
    }
    
    private var previousPage: Page = .Main
    
    // MARK: Life Cycle
    
    public override func viewDidLoad() {
        MisskeyKit.auth.setAPIKey("27929d28b8549999fe11dca576f92c6898561a651a8fd9f979f83c9b49b05703")
        
        needBorder = true
        selectedBarHeight = 2
        selectedBar.layer.cornerRadius = 2
        selectedBar.backgroundColor = .systemBlue
        selectedBarMargins.lower += 1
        sectionInset = .init(top: 0, left: 20, bottom: 0, right: 5)
        tabBackgroundColor = .white
        view.backgroundColor = .white
        
        navBar.isHidden = true
        
        if !isXSeries {
            selectedBarMargins.upper += 3
            selectedBarMargins.lower += 1
            sectionInset = .init(top: 2, left: 10, bottom: 0, right: 5)
        }
        
        super.viewDidLoad()
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        navigationController?.delegate = self
        navigationController?.interactivePopGestureRecognizer?.delegate = self
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        
        guard !initialized else { return }
        
        setupFooterTab()
        showNotificationBanner(icon: .Loading, notification: "ロード中...")
        initialized = true
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        setupNotificationsVC() // 先にNotificationsVCをロードしておく → 通知のロードを裏で行う
        setupNavTab()
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
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
            notificationsViewController.view.isHidden = true
            notificationsViewController.homeViewController = self
            self.notificationsViewController = notificationsViewController
            
            navBar.barTitle = "Notifications"
            navBar.setButton(style: .None, rightFont: nil, leftFont: nil)
            
            addChild(self.notificationsViewController!)
            view.addSubview(self.notificationsViewController!.view)
            view.bringSubviewToFront(navBar)
            view.bringSubviewToFront(footerTab)
        }
        
        notificationsViewController!.view.frame = getDisplayRect()
    }
    
    // MARK: FooterTab's Pages
    
    // 下タブに対応するViewControllerを操作するメソッド群
    
    private func showNotificationsView() {
        guard let notificationsViewController = notificationsViewController else { return }
        
        navBar.isHidden = false
        navBar.barTitle = "Notifications"
        navBar.setButton(style: .None, rightFont: nil, leftFont: nil)
        
        nowPage = .Notifications
        notificationsViewController.view.isHidden = false
    }
    
    // MARK: Other Pages
    
    private func showPostDetailView(item: NoteCell.Model) {
        guard let storyboard = self.storyboard else { return }
        guard let detailViewController = storyboard.instantiateViewController(withIdentifier: "post-detail") as? PostDetailViewController else { return }
        
        detailViewController.view.frame = getDisplayRect()
        detailViewController.item = item
        
        //        self.addChild(detailViewController)
        //        self.view.addSubview(detailViewController.view)
        navigationController?.pushViewController(detailViewController, animated: true)
        
        nowPage = .PostDetails
//        self.navBar.isHidden = false
//        self.navBar.barTitle = ""
//        self.navBar.setButton(style: .Left, leftText: "chevron-left", leftFont: .awesomeSolid(fontSize: 16.0))
        
        view.bringSubviewToFront(navBar)
        view.bringSubviewToFront(footerTab)
        
        self.detailViewController = detailViewController
    }
    
    private func showProfileView(userId: String, isMe: Bool = false) {
        nowPage = .Profile
        if isMe, let myProfileViewController = myProfileViewController {
            myProfileViewController.view.isHidden = false
            return
        }
        
        // If myProfileViewController, currentProfileViewController is nil...
        guard let storyboard = self.storyboard,
            let profileViewController = storyboard.instantiateViewController(withIdentifier: "profile") as? ProfileViewController else { return }
        
        profileViewController.setUserId(userId, isMe: isMe)
        profileViewController.view.frame = getDisplayRect(needNavBar: false)
        
        if isMe {
            addChild(profileViewController)
            view.addSubview(profileViewController.view)
            myProfileViewController = profileViewController
        } else {
            navigationController?.pushViewController(profileViewController, animated: true)
        }
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
        case .Main:
            tappedHome()
            
        case .Notifications:
            tappedNotifications()
            
        default:
            return
        }
    }
    
    private func generateTimelineVC(type: TimelineType) -> TimelineViewController {
        guard let viewController = self.getViewController(name: "timeline") as? TimelineViewController
        else { fatalError("Internal Error.") }
        
        viewController.setup(type: type)
        return viewController
    }
    
    private func hideView(without type: Page) {
        if type != .Notifications, let notificationsViewController = notificationsViewController {
            notificationsViewController.view.isHidden = true
            navBar.isHidden = true
        }
        
        if type != .Profile, let myProfileViewController = self.myProfileViewController {
            myProfileViewController.view.isHidden = true
        }
        if type != .Profile, let currentProfileViewController = self.currentProfileViewController {
            currentProfileViewController.view.isHidden = true
        }
    }
    
    private func showNotificationBanner(icon: NotificationBanner.IconType, notification: String) {
        let bannerWidth = view.frame.width / 3
        
        let frame = CGRect(x: view.frame.width - bannerWidth - 10,
                           y: footerTab.frame.origin.y - 30,
                           width: bannerWidth,
                           height: 30)
        
        let notificationBanner = NotificationBanner(frame: frame, icon: icon, notification: notification)
        view.addSubview(notificationBanner)
        view.bringSubviewToFront(notificationBanner)
    }
    
    // MARK: FooterTabBar Delegate
    
    public func tappedHome() {
        if nowPage != .Main {
            nowPage = .Main
            DispatchQueue.main.async { self.hideView(without: .Main) }
        } else {
            home.tappedHome()
        }
    }
    
    public func tappedNotifications() {
        guard let notificationsViewController = notificationsViewController else { return }
        
        if nowPage == .Notifications {
            guard let notificationsView = notificationsViewController as? FooterTabBarDelegate else { return }
            notificationsView.tappedNotifications()
        } else {
            DispatchQueue.main.async { self.hideView(without: .Notifications) }
            showNotificationsView()
        }
    }
    
    public func tappedPost() {
        nowPage = .Post
        move2ViewController(identifier: "post")
    }
    
    public func tappedFav() {
        home.tappedFav()
    }
    
    public func tappedProfile() {
        guard nowPage != .Profile else { return }
        
        Cache.shared.getMe { me in
            guard let me = me else { return }
            DispatchQueue.main.async {
                self.hideView(without: .Profile)
                self.showProfileView(userId: me.id, isMe: true)
            }
        }
    }
    
    // MARK: NavBar Delegate
    
    public func tappedLeftNavButton() {
        if nowPage == .PostDetails {
            guard let detailViewController = detailViewController else { return }
            detailViewController.view.removeFromSuperview()
            
            backNavBarStatus() // NavBarの表示を元に戻す
        }
    }
    
    public func tappedRightNavButton() {}
    
    // MARK: Timeline Delegate
    
    public func tappedCell(item: NoteCell.Model) {
        showPostDetailView(item: item)
    }
    
    public func move2Profile(userId: String) {
        showProfileView(userId: userId)
    }
    
    public func openUserPage(username: String) {
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
        
        MisskeyKit.users.showUser(username: _username, host: host) { user, error in
            guard error == nil, let user = user else { return }
            DispatchQueue.main.async {
                self.showProfileView(userId: user.id)
            }
        }
    }
    
    public func successInitialLoading(_ success: Bool) {
        guard !success else { return }
        
        showNotificationBanner(icon: .Failed, notification: "投稿の取得に失敗しました")
    }
    
    public func changedStreamState(success: Bool) {
        guard !success else { return }
        showNotificationBanner(icon: .Failed, notification: "Streamingが切断されました")
    }
    
    // MARK: NavigationController Delegate
    
    public func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        if viewController is HomeViewController {
            nowPage = .Main
        } else if viewController is ProfileViewController {
            nowPage = .Profile
        }
    }
    
    // MARK: PolioPager Delegate
    
    public override func tabItems() -> [TabItem] {
        return [TabItem(title: "Home", backgroundColor: UIColor(hex: "ECECEC")),
                TabItem(title: "Local", backgroundColor: UIColor(hex: "ECECEC")),
                TabItem(title: "Global", backgroundColor: UIColor(hex: "ECECEC"))]
    }
    
    public override func viewControllers() -> [UIViewController] {
        return [search, home, local, global]
    }
}

extension HomeViewController {
    public enum Page {
        // FooterTab
        case Main
        case Notifications
        case Post
        case Profile
        
        // Others
        case PostDetails
    }
}
