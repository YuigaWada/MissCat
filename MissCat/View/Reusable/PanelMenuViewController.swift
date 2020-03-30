//
//  PanelMenuViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/07.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxSwift
import UIKit

class PanelMenuViewController: UIViewController {
    @IBOutlet weak var panelTitleLabel: UILabel!
    @IBOutlet weak var stackView: UIStackView!
    @IBOutlet weak var stackViewHeightContraint: NSLayoutConstraint!
    
    private var panelTitle: String = ""
    private var itemViews: [UIView] = []
    private var disposeBag = DisposeBag()
    
    var tapTrigger: Observable<Int> = Observable.of(-1) // タップされたらどの選択肢がおされたのか(=order)を流す
    
    func setPanelTitle(_ title: String) {
        panelTitle = title
    }
    
    func setupMenu(items: [MenuItem]) {
        items.forEach { item in
            itemViews.append(self.getMenuItemView(with: item))
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        panelTitleLabel.text = panelTitle
        
        guard stackView.arrangedSubviews.count == 0 else { return }
        
        stackViewHeightContraint.constant = CGFloat((itemViews.count - 1) * 30 + itemViews.count * 50)
        itemViews.forEach { itemView in
            
            stackView.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(itemView)
            stackView.addConstraints([
                NSLayoutConstraint(item: itemView,
                                   attribute: .height,
                                   relatedBy: .equal,
                                   toItem: stackView,
                                   attribute: .height,
                                   multiplier: 0,
                                   constant: 50)
            ])
        }
    }
    
    /// メニュー選択肢となるviewを取得する
    /// - Parameter item: MenuItem
    private func getMenuItemView(with item: MenuItem) -> UIView {
//        let theme = Theme.shared.getCurrentTheme()
        let menuView = UIView()
        
        menuView.layer.cornerRadius = 10
        menuView.backgroundColor = .systemBlue
        
        // label: アイコン
        let iconLabel = UILabel()
        iconLabel.text = item.awesomeIcon
        iconLabel.font = .awesomeSolid(fontSize: 25.0)
        iconLabel.textColor = .white
        iconLabel.minimumScaleFactor = 0.1
        
        iconLabel.sizeToFit()
        iconLabel.isUserInteractionEnabled = true
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        menuView.addSubview(iconLabel)
        
        // label: 選択肢のlabel
        let titleLabel = UILabel()
        titleLabel.text = item.title
        titleLabel.font = .systemFont(ofSize: 20.0)
        titleLabel.textColor = .white
        
        titleLabel.sizeToFit()
        titleLabel.isUserInteractionEnabled = true
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
                               constant: 50),
            
            NSLayoutConstraint(item: iconLabel,
                               attribute: .height,
                               relatedBy: .equal,
                               toItem: menuView,
                               attribute: .height,
                               multiplier: 0,
                               constant: 30),
            
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
    struct MenuItem {
        let title: String
        let awesomeIcon: String
        
        var order: Int = 0
    }
}
