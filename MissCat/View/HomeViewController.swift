//
//  HomeViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/16.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit
import PolioPager
import MisskeyKit

// **    方針    **
// 基本的にはMVVMパターンを採用し、View / UIViewControllerの管理はこのHomeViewControllerが行う。
// 上タブ管理はBGで動いている親クラスのPolioPagerが行い、下タブ管理はHomeViewControllerが自前で行う。


// 各Timeline: それぞれのtimelineの情報をそれぞれのview上で行う / Streamingは"hogehoge timeline"チャンネルを通す。
//  | ← 上タブ管理
// HomeViewController: 上下のタブを管理し、すべてのViewはこのvc上で動かす ＝ 画面遷移はすべてこのVCに委譲する
//  | ← 通知のバインディング
// NotificationsViewController: 通知を管理 / Streamingは"main"チャンネルを通す / UserDefaultsで最新通知のidを永続化



// (OOPの対極的存在である)一時的なキャッシュ管理についてはsingletonのCacheクラスを使用。

public class HomeViewController: PolioPagerViewController, FooterTabBarDelegate, TimelineDelegate, NavBarDelegate {
    private var isXSeries = UIScreen.main.bounds.size.height > 811
    private let footerTabHeight: CGFloat = 55
    
    
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
            self.previousPage = nowPage
        }
    }
    private var previousPage: Page = .Main
    
    
    
    
    //MARK: Life Cycle
    override public func viewDidLoad() {
        MisskeyKit.auth.setAPIKey("27929d28b8549999fe11dca576f92c6898561a651a8fd9f979f83c9b49b05703")
        
        self.needBorder = true
        self.selectedBarHeight = 2
        self.selectedBar.layer.cornerRadius = 2
        self.selectedBar.backgroundColor = .darkGray
        self.selectedBarMargins.lower += 1
        self.sectionInset = .init(top: 0, left: 20, bottom: 0, right: 5)
        self.tabBackgroundColor = UIColor(hex: "ECECEC")
        self.view.backgroundColor = UIColor(hex: "ECECEC")
        
        self.navBar.isHidden = true
        
        if !isXSeries {
            self.selectedBarMargins.upper += 3
            self.selectedBarMargins.lower += 1
            self.sectionInset = .init(top: 2, left: 10, bottom: 0, right: 5)
        }
        
        super.viewDidLoad()
    }
    
    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.setupFooterTab()
    }
    
    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.setupNotificationsVC() // 先にNotificationsVCをロードしておく → 通知のロードを裏で行う
        self.setupNavTab()
    }
    
    
    
    
    //MARK: Setup Tab
    private func setupFooterTab() {
        
        footerTab.frame = self.getFooterTabSize(height: self.footerTabHeight)
        self.view.addSubview(footerTab)
        
        footerTab.delegate = self
        footerTab.selected = .home
    }
    
    private func setupNavTab() {
        if !hasPreparedViews {
            self.view.addSubview(self.navBar)
            hasPreparedViews = true
        }
        
        self.navBar.delegate = self
        self.navBar.frame = CGRect(x: 0,
                                   y: 0,
                                   width: self.view.frame.width,
                                   height: self.pageView.frame.origin.y)
        
        
    }
    
    
    //MARK: Setup Initial View
    private func setupNotificationsVC() {
        if self.notificationsViewController == nil {
            guard let storyboard = self.storyboard else { return }
            self.notificationsViewController = storyboard.instantiateViewController(withIdentifier: "notifications")
            self.notificationsViewController!.view.isHidden = true
            
            self.navBar.barTitle = "Notifications"
            self.navBar.setButton(style: .None, rightFont: nil, leftFont: nil)
            
            self.addChild(self.notificationsViewController!)
            self.view.addSubview(self.notificationsViewController!.view)
            self.view.bringSubviewToFront(self.navBar)
            self.view.bringSubviewToFront(self.footerTab)
        }
        
        self.notificationsViewController!.view.frame = self.getDisplayRect()
    }
    
    
    
    
    
    //MARK: FooterTab's Pages
    //下タブに対応するViewControllerを操作するメソッド群
    
    private func showNotificationsView() {
        guard let notificationsViewController = notificationsViewController else { return }
        
        self.navBar.isHidden = false
        self.navBar.barTitle = "Notifications"
        self.navBar.setButton(style: .None, rightFont: nil, leftFont: nil)
        
        self.nowPage = .Notifications
        notificationsViewController.view.isHidden = false
    }
    
    
    
    //MARK: Other Pages
    private func showPostDetailView(item: NoteCell.Model) {
        guard let storyboard = self.storyboard else { return }
        guard let detailViewController = storyboard.instantiateViewController(withIdentifier: "post-detail") as? PostDetailViewController else { return }
        
        detailViewController.view.frame = self.getDisplayRect()
        detailViewController.item = item
        
        self.addChild(detailViewController)
        self.view.addSubview(detailViewController.view)
        
        self.nowPage = .PostDetails
        self.navBar.isHidden = false
        self.navBar.barTitle = ""
        self.navBar.setButton(style: .Left, leftText: "chevron-left", leftFont: .awesomeSolid(fontSize: 16.0))
        
        self.view.bringSubviewToFront(self.navBar)
        self.view.bringSubviewToFront(self.footerTab)
        
        self.detailViewController = detailViewController
    }
    
    private func showProfileView(userId: String, isMe: Bool = false) {
        if isMe, let myProfileViewController = myProfileViewController {
            myProfileViewController.view.isHidden = false
            return
        }
        else if !isMe, let currentProfileViewController = currentProfileViewController {
            currentProfileViewController.view.isHidden = false
            return
        }
        
        // If myProfileViewController, currentProfileViewController is nil...
        guard let storyboard = self.storyboard,
            let vc = storyboard.instantiateViewController(withIdentifier: "profile") as? ProfileViewController else { return }
        
        vc.setUserId(userId)
        vc.view.frame = self.getDisplayRect(needNavBar: false)
        
        self.nowPage = .Profile
        self.addChild(vc)
        self.view.addSubview(vc.view)
        
        if isMe {
            self.myProfileViewController = vc
        }
        else {
            self.currentProfileViewController = vc
        }
    }
    
    
    //MARK: Utilities
    private func getViewController(name: String)-> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyboard.instantiateViewController(withIdentifier: name)
        
        guard let timelineViewController = viewController as? TimelineViewController else { return viewController }
        timelineViewController.homeViewController = self
        
        return timelineViewController
    }
    
    
    
    private func getDisplayRect(needNavBar: Bool = true)-> CGRect {
        let pageHeight = self.pageView.frame.height - (self.view.frame.height - self.footerTab.frame.origin.y)
        let navBarHeight = self.pageView.frame.origin.y
        
        let y = needNavBar ? self.pageView.frame.origin.y : 0
        let height = pageHeight + (needNavBar ? 0 : navBarHeight)
        
        
        return CGRect(x: 0,
                      y: y,
                      width: self.view.frame.width,
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
    
    private func generateTimelineVC(type: TimelineType)-> TimelineViewController {
        guard let viewController = self.getViewController(name: "timeline") as? TimelineViewController
            else { fatalError("Internal Error.") }
        
        viewController.setup(type: type)
        return viewController
    }
    
    private func hideView(without type: Page) {
        if type != .Notifications, let notificationsViewController = notificationsViewController {
            notificationsViewController.view.isHidden = true
        }
        
        if type != .Profile, let myProfileViewController = self.myProfileViewController {
            myProfileViewController.view.isHidden = true
        }
    }
    
    
    //MARK: FooterTabBar Delegate
    public func tappedHome() {
        if self.nowPage != .Main {
            self.nowPage = .Main
            self.navBar.isHidden = true
            DispatchQueue.main.async { self.hideView(without: .Main) }
        }
        else {
            guard let home = home as? FooterTabBarDelegate else { return }
            home.tappedHome()
        }
    }
    
    public func tappedNotifications() {
        guard let notificationsViewController = notificationsViewController else { return }
        
        if self.nowPage == .Notifications {
            guard let notificationsView = notificationsViewController as? FooterTabBarDelegate else { return }
            notificationsView.tappedNotifications()
        }
        else {
            DispatchQueue.main.async { self.hideView(without: .Notifications) }
            self.showNotificationsView()
        }
    }
    
    public func tappedPost() {
        self.nowPage = .Post
        self.move2ViewController(identifier: "post")
    }
    
    public func tappedFav() {
        guard let home = home as? FooterTabBarDelegate else { return }
        home.tappedFav()
    }
    
    public func tappedProfile() {
        guard self.nowPage != .Profile else { return }
        
        Cache.shared.getMe { me in
            guard let me = me else { return }
            DispatchQueue.main.async { self.showProfileView(userId: me.id, isMe: true) }
        }
    }
    
    
    //MARK: NavBar Delegate
    public func tappedLeftNavButton() {
        if nowPage == .PostDetails {
            guard let detailViewController = detailViewController else { return }
            detailViewController.view.removeFromSuperview()
            
            self.backNavBarStatus() //NavBarの表示を元に戻す
        }
    }
    
    public func tappedRightNavButton() {
        
    }
    
    
    //MARK: Timeline Delegate
    public func tappedCell(item: NoteCell.Model) {
        self.showPostDetailView(item: item)
    }
    
    public func move2Profile(userId: String) {
        self.showProfileView(userId: userId)
    }
    
    
    
    
    
    //MARK: PolioPager Delegate
    override public func tabItems()-> [TabItem] {
        return [TabItem(title: "Home", backgroundColor: UIColor(hex: "ECECEC")),
                TabItem(title: "Local", backgroundColor: UIColor(hex: "ECECEC")),
                TabItem(title: "Global", backgroundColor: UIColor(hex: "ECECEC"))]
    }
    
    override public func viewControllers()-> [UIViewController]
    {
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
