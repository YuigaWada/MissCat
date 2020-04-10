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
    // MARK: IBOutlet
    
    @IBOutlet weak var timelineView: UIView!
    
    // MARK: PolioPager
    
    var searchBar: UIView!
    var searchTextField: UITextField!
    var cancelButton: UIButton!
    
    // MARK: Vars
    
    var homeViewController: HomeViewController?
    private var timelineVC: TimelineViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        searchTextField.delegate = self
    }
    
//    private func getSearchTrigger() -> Observable<String> {
//        let debounceInterval = DispatchTimeInterval.milliseconds(300)
//        return searchBar.rx.text.compactMap { $0?.localizedLowercase }.asObservable()
//            .skip(1)
//            .debounce(debounceInterval, scheduler: MainScheduler.instance)
//            .distinctUntilChanged()
//    }
    
    // MARK: Utilities
    
    private func generateTimelineVC(query: String) -> TimelineViewController {
        guard let viewController = getViewController(name: "timeline") as? TimelineViewController
        else { fatalError("Internal Error.") }
        
        viewController.setup(type: .NoteSearch, query: query)
        viewController.view.frame = timelineView.frame
        timelineView.addSubview(viewController.view)
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
        
        let timelineVC = generateTimelineVC(query: query)
        self.timelineVC = timelineVC
        
        return true
    }
    
    // キーボードを閉じる
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
