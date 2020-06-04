//
//  SearchViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/11.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import PolioPager
import RxCocoa
import RxSwift
import UIKit

class SearchViewController: UIViewController, PolioPagerSearchTabDelegate, UITextFieldDelegate {
    // MARK: UIView
    
    @IBOutlet weak var timelineView: UIView!
    
    @IBOutlet weak var searchLabel: UILabel!
    @IBOutlet weak var noteTab: UIButton!
    @IBOutlet weak var userTab: UIButton!
    @IBOutlet weak var tabContainer: UIView!
    
    private var noteQuery: String?
    private var userQuery: String?
    private lazy var tabIndicator: UIView = .init()
    
    // MARK: PolioPager
    
    var searchBar: UIView!
    var searchTextField: UITextField! {
        didSet {
            searchTextField.delegate = self
            searchTextField.textColor = Theme.shared.currentModel?.colorPattern.ui.text ?? .black
            searchTextField.changePlaceholderColor(to: Theme.shared.currentModel?.colorPattern.ui.sub2 ?? .black)
        }
    }
    
    var cancelButton: UIButton! {
        didSet {
            setupCancelButton()
        }
    }
    
    // MARK: Vars
    
    var homeViewController: HomeViewController?
    private var trendVC: TrendViewController?
    private var timelineVC: TimelineViewController?
    private var userListVC: UserListViewController?
    
    private var selected: Tab = .note
    
    private var mainColor: UIColor = .systemBlue
    private let disposeBag: DisposeBag = .init()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        bindTheme()
        setTheme()
        
        setupTrends()
        setupTab()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    // MARK: Design
    
    private func bindTheme() {
        let theme = Theme.shared.theme
        
        theme.map { UIColor(hex: $0.mainColorHex) }.subscribe(onNext: { color in
            self.tabIndicator.backgroundColor = color
            self.mainColor = color
        }).disposed(by: disposeBag)
        
        theme.map { $0.colorPattern.ui }.subscribe(onNext: { colorPattern in
            self.searchLabel.textColor = colorPattern.text
            self.searchTextField?.textColor = colorPattern.text
            self.searchTextField?.changePlaceholderColor(to: colorPattern.sub2)
        }).disposed(by: disposeBag)
    }
    
    private func setTheme() {
        if let mainColorHex = Theme.shared.currentModel?.mainColorHex {
            mainColor = UIColor(hex: mainColorHex)
            tabIndicator.backgroundColor = mainColor
        }
        
        if let colorPattern = Theme.shared.currentModel?.colorPattern.ui {
            searchLabel.textColor = colorPattern.text
        }
    }
    
    private func setupTrends() {
        guard let trendVC = getViewController(name: "trend") as? TrendViewController else { return }
        
        trendVC.view.frame = view.frame
        trendVC.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(trendVC.view)
        setAutoLayout(to: trendVC.view)
        addChild(trendVC)
        
        trendVC.tappedTable.subscribe(onNext: { tag in
            self.animateTrend(trendIsHidden: true)
            self.searchNote(with: tag)
        }).disposed(by: disposeBag)
        
        self.trendVC = trendVC
    }
    
    // MARK: Publics
    
    func searchNote(with text: String) {
        selected = .note
        tabContainer.alpha = 1
        trendVC?.view.alpha = 0
        tabContainer.isHidden = false
        trendVC?.view.isHidden = true
        animateTab(next: .note) {
            self.searchTextField.text = text
            self.search(with: text)
        }
    }
    
    // MARK: Privates
    
    private func search(with query: String) {
        var query = query
        
        if query.count > 0 {
            let space = [" ", "　"]
            if space.filter({ query.suffix(1) == $0 }).count > 0 { // 最末端の空白を取り除く
                query = String(query.prefix(query.count - 1))
            }
        }
        
        if query.isEmpty {
            animateTrend(trendIsHidden: false)
        }
        switch selected {
        case .note:
            guard query != noteQuery else { return }
            removeTimelineVC()
            if let timelineVC = generateTimelineVC(query: query) {
                self.timelineVC = timelineVC
                noteQuery = query
            }
            
        case .user:
            guard query != userQuery else { return }
            removeUserListVC()
            if let userListVC = generateUserListVC(query: query) {
                self.userListVC = userListVC
                userQuery = query
            }
            
        case .moving:
            break
        }
    }
    
    // MARK: Design
    
    private func setupTab() {
        guard tabIndicator.frame == .zero else { return }
        
        tabIndicator.frame = noteTab.frame.insetBy(dx: -4, dy: 0)
        tabIndicator.backgroundColor = mainColor
        
        userTab.setTitleColor(.lightGray, for: .normal)
        noteTab.setTitleColor(.white, for: .normal)
        
        noteTab.rx.tap.subscribe(onNext: { _ in
            guard self.selected != .note else { return }
            self.animateTab(next: .note)
        }).disposed(by: disposeBag)
        
        userTab.rx.tap.subscribe(onNext: { _ in
            guard self.selected != .user else { return }
            self.animateTab(next: .user)
        }).disposed(by: disposeBag)
        
        tabIndicator.layer.cornerRadius = 5
        tabContainer.addSubview(tabIndicator)
        tabContainer.bringSubviewToFront(noteTab)
        tabContainer.bringSubviewToFront(userTab)
        
        tabContainer.isHidden = true
        tabContainer.alpha = 0
    }
    
    private func animateTab(next: Tab, completion: (() -> Void)? = nil) {
        guard selected != .moving,
            let nextTab = next == .note ? noteTab : userTab,
            let previousTab = next == .note ? userTab : noteTab else { return }
        
        selected = .moving
        let nextVC = next == .note ? timelineVC : userListVC
        let previousVC = next == .note ? userListVC : timelineVC
        
        nextVC?.view.alpha = 0
        nextVC?.view.isHidden = false
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut, animations: {
            self.tabIndicator.frame = nextTab.frame.insetBy(dx: -4, dy: 0)
            
            previousVC?.view.alpha = 0
            nextVC?.view.alpha = 1
        }, completion: { fin in
            guard fin else { return }
            self.selected = next
            
            // vc
            previousVC?.view.isHidden = true
            
            // tab
            nextTab.setTitleColor(.white, for: .normal)
            previousTab.setTitleColor(.lightGray, for: .normal)
            
            if let preQuery = next == .note ? self.userQuery : self.noteQuery {
                self.search(with: preQuery)
            }
            
            completion?()
        })
    }
    
    private func animateTrend(trendIsHidden: Bool, completion: (() -> Void)? = nil) {
        guard let trendView = trendVC?.view else { return }
        
        if trendIsHidden, let currentTab = selected == .note ? noteTab : userTab {
            tabIndicator.frame = currentTab.frame.insetBy(dx: -4, dy: 0)
        }
        view.bringSubviewToFront(tabContainer)
        view.bringSubviewToFront(trendView)
        UIView.animate(withDuration: 0.35, delay: 0, options: .curveEaseInOut, animations: {
            self.tabContainer.alpha = trendIsHidden ? 1 : 0
            trendView.alpha = trendIsHidden ? 0 : 1
        }, completion: { fin in
            guard fin else { return }
            self.tabContainer.isHidden = !trendIsHidden
            trendView.isHidden = trendIsHidden
            completion?()
        })
    }
    
    private func setupCancelButton() {
        cancelButton.rx.tap.subscribe(onNext: { _ in
            self.userQuery = nil
            self.noteQuery = nil
            self.searchTextField.text = nil
            
            self.removeTimelineVC()
            self.removeUserListVC()
            
            self.tabContainer.alpha = 0
            self.trendVC?.view.alpha = 1
            
            self.tabContainer.isHidden = true
            self.trendVC?.view.isHidden = false
        }).disposed(by: disposeBag)
    }
    
    // MARK: Utilities
    
    private func generateTimelineVC(query: String) -> TimelineViewController? {
        guard !query.isEmpty,
            let viewController = getViewController(name: "timeline") as? TimelineViewController,
            let owner = Cache.UserDefaults.shared.getCurrentUser() else { return nil }
        
        viewController.setup(owner: owner, type: .NoteSearch, query: query, lockScroll: false, withTopShadow: true)
        viewController.view.frame = timelineView.frame
        viewController.view.translatesAutoresizingMaskIntoConstraints = false
        timelineView.addSubview(viewController.view)
        setAutoLayout(to: viewController.view)
        addChild(viewController)
        
        return viewController
    }
    
    private func generateUserListVC(query: String) -> UserListViewController? {
        guard !query.isEmpty,
            let viewController = getViewController(name: "user-list") as? UserListViewController,
            let owner = Cache.UserDefaults.shared.getCurrentUser() else { return nil }
        
        viewController.setup(type: .search, owner: owner, query: query, lockScroll: false, withTopShadow: true)
        viewController.view.frame = timelineView.frame
        viewController.view.translatesAutoresizingMaskIntoConstraints = false
        timelineView.addSubview(viewController.view)
        setAutoLayout(to: viewController.view)
        addChild(viewController)
        
        return viewController
    }
    
    private func getViewController(name: String) -> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyboard.instantiateViewController(withIdentifier: name)
        
        guard let timelineViewController = viewController as? NoteDisplay else { return viewController }
        timelineViewController.homeViewController = homeViewController
        
        return timelineViewController
    }
    
    private func removeTimelineVC() {
        guard let timelineVC = timelineVC else { return }
        
        timelineVC.removeFromParent()
        timelineVC.view.removeFromSuperview()
        self.timelineVC = nil
        noteQuery = nil
    }
    
    private func removeUserListVC() {
        guard let userListVC = userListVC else { return }
        
        userListVC.removeFromParent()
        userListVC.view.removeFromSuperview()
        self.userListVC = nil
        userQuery = nil
    }
    
    private func setAutoLayout(to view: UIView) {
        self.view.addConstraints([
            NSLayoutConstraint(item: view,
                               attribute: .width,
                               relatedBy: .equal,
                               toItem: timelineView,
                               attribute: .width,
                               multiplier: 1.0,
                               constant: 0),
            
            NSLayoutConstraint(item: view,
                               attribute: .height,
                               relatedBy: .equal,
                               toItem: timelineView,
                               attribute: .height,
                               multiplier: 1.0,
                               constant: 0),
            
            NSLayoutConstraint(item: view,
                               attribute: .centerX,
                               relatedBy: .equal,
                               toItem: timelineView,
                               attribute: .centerX,
                               multiplier: 1.0,
                               constant: 0),
            
            NSLayoutConstraint(item: view,
                               attribute: .centerY,
                               relatedBy: .equal,
                               toItem: timelineView,
                               attribute: .centerY,
                               multiplier: 1.0,
                               constant: 0)
        ])
    }
    
    // MARK: Delegate
    
    // フォーカスされる時
    func textFieldDidBeginEditing(_ textField: UITextField) {
        animateTrend(trendIsHidden: true)
    }
    
    // フォーカスが外れる前
    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        guard let query = textField.text else { removeTimelineVC(); return true }
        
        search(with: query)
        return true
    }
    
    // キーボードを閉じる
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

extension SearchViewController {
    enum Tab {
        case note
        case user
        case moving
    }
}

extension UITextField {
    /// placeholderの色を変更する
    /// - Parameter placeholderColor: UIColor
    func changePlaceholderColor(to placeholderColor: UIColor) {
        attributedPlaceholder = .init(string: placeholder ?? "",
                                      attributes: [.foregroundColor: placeholderColor])
    }
}
