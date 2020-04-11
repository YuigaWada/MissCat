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
    
    @IBOutlet weak var noteTab: UIButton!
    @IBOutlet weak var userTab: UIButton!
    @IBOutlet weak var tabContainer: UIView!
    
    private var query: String?
    private lazy var tabIndicator: UIView = .init()
    
    // MARK: PolioPager
    
    var searchBar: UIView!
    var searchTextField: UITextField! {
        didSet {
            searchTextField.delegate = self
        }
    }
    
    var cancelButton: UIButton!
    
    // MARK: Vars
    
    var homeViewController: HomeViewController?
    private var timelineVC: TimelineViewController?
    
    private var selected: Tab = .note
    
    private let disposeBag: DisposeBag = .init()
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setupTab()
    }
    
    // MARK: Publics
    
    func searchNote(with text: String) {
        selected = .note
        animateTab(next: .note)
        
        searchTextField.text = text
        search(with: text)
    }
    
    // MARK: Privates
    
    private func search(with query: String) {
        guard query != self.query else { return }
        
        removeTimelineVC()
        let timelineVC = generateTimelineVC(query: query)
        self.timelineVC = timelineVC
        self.query = query
    }
    
    // MARK: Design
    
    private func setupTab() {
        guard tabIndicator.frame == .zero else { return }
        
        tabIndicator.frame = noteTab.frame.insetBy(dx: -4, dy: 0)
        tabIndicator.backgroundColor = .systemBlue
        
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
    }
    
    private func animateTab(next: Tab) {
        guard selected != .moving,
            let target = next == .note ? noteTab : userTab,
            let previous = next == .note ? userTab : noteTab else { return }
        
        selected = .moving
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut, animations: {
            self.tabIndicator.frame = target.frame.insetBy(dx: -4, dy: 0)
        }, completion: { fin in
            guard fin else { return }
            self.selected = next
            target.setTitleColor(.white, for: .normal)
            previous.setTitleColor(.lightGray, for: .normal)
        })
    }
    
    // MARK: Utilities
    
    private func generateTimelineVC(query: String) -> TimelineViewController {
        guard let viewController = getViewController(name: "timeline") as? TimelineViewController
        else { fatalError("Internal Error.") }
        
        viewController.setup(type: .NoteSearch, query: query, withTopShadow: true)
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
        
        guard let timelineViewController = viewController as? TimelineViewController else { return viewController }
        timelineViewController.homeViewController = homeViewController
        
        return timelineViewController
    }
    
    private func removeTimelineVC() {
        guard let timelineVC = timelineVC else { return }
        
        timelineVC.removeFromParent()
        timelineVC.view.removeFromSuperview()
        self.timelineVC = nil
        query = nil
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
    
    // フォーカスが外れる前
    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        guard let query = textField.text, !query.isEmpty else { removeTimelineVC(); return true }
        
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
