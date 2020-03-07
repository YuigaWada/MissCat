//
//  PanelMenuViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/07.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxSwift
import UIKit

public class PanelMenuViewController: UIViewController {
    @IBOutlet weak var stackView: UIStackView!
    @IBOutlet weak var stackViewHeightContraint: NSLayoutConstraint!
    
    private var items: [MenuItem] = []
    private var disposeBag = DisposeBag()
    
    public var tapTrigger: Observable<Int> = Observable.of(-1) // タップされたらどの選択肢がおされたのか(=order)を流す
    
    public func setupMenu(items: [MenuItem]) {
        self.items = items
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        guard stackView.arrangedSubviews.count == 0 else { return }
        
        stackViewHeightContraint.constant = CGFloat((items.count - 1) * 50)
        items.forEach { item in
            let itemView = self.getMenuItemView(with: item)
            stackView.addArrangedSubview(itemView)
            stackViewHeightContraint.constant += itemView.frame.height
        }
    }
    
    /// メニュー選択肢となるviewを取得する
    /// - Parameter item: MenuItem
    private func getMenuItemView(with item: MenuItem) -> UIView {
        let menuView = UIView()
        
        // label: アイコン
        let iconLabel = UILabel()
        iconLabel.text = item.awesomeIcon
        iconLabel.font = .awesomeSolid(fontSize: 25.0)
        iconLabel.textColor = .lightGray
        
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        menuView.addSubview(iconLabel)
        
        // label: アイコン
        let titleLabel = UILabel()
        titleLabel.text = item.title
        titleLabel.font = .systemFont(ofSize: 20.0)
        titleLabel.textColor = .lightGray
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        menuView.addSubview(titleLabel)
        
        // AutoLayout
        menuView.addConstraints([
            NSLayoutConstraint(item: iconLabel,
                               attribute: .width,
                               relatedBy: .equal,
                               toItem: menuView,
                               attribute: .width,
                               multiplier: 0,
                               constant: 25),
            
            NSLayoutConstraint(item: iconLabel,
                               attribute: .height,
                               relatedBy: .equal,
                               toItem: menuView,
                               attribute: .height,
                               multiplier: 0,
                               constant: 25),
            
            NSLayoutConstraint(item: iconLabel,
                               attribute: .left,
                               relatedBy: .equal,
                               toItem: menuView,
                               attribute: .left,
                               multiplier: 1.0,
                               constant: 20),
            
            NSLayoutConstraint(item: iconLabel,
                               attribute: .centerY,
                               relatedBy: .equal,
                               toItem: menuView,
                               attribute: .centerY,
                               multiplier: 1.0,
                               constant: 0)
        ])
        
        menuView.addConstraints([
            NSLayoutConstraint(item: titleLabel,
                               attribute: .left,
                               relatedBy: .equal,
                               toItem: iconLabel,
                               attribute: .left,
                               multiplier: 1.0,
                               constant: 40),
            
            NSLayoutConstraint(item: titleLabel,
                               attribute: .centerY,
                               relatedBy: .equal,
                               toItem: menuView,
                               attribute: .centerY,
                               multiplier: 1.0,
                               constant: 0)
        ])
        
        
        
        setupTapGesture(to: menuView, tappedItem: item)
        return menuView
    }
    
    /// タップジェスチャーをsetする
    /// - Parameters:
    ///   - view: 対象のview
    ///   - tappedItem: MenuItem
    private func setupTapGesture(to target: UIView, tappedItem: MenuItem) {
        let tapGesture = UITapGestureRecognizer()
        let tapEvent = tapGesture.rx.event.map { _ in
            tappedItem.order
        }
        target.isUserInteractionEnabled = true
        target.addGestureRecognizer(tapGesture)
        
        tapTrigger = Observable.of(tapTrigger, tapEvent).merge()
    }
}

extension PanelMenuViewController {
    public struct MenuItem {
        let title: String
        let awesomeIcon: String
        
        var order: Int = 0
    }
}
