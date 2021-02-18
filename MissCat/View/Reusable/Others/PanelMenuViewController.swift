//
//  PanelMenuViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/07.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxCocoa
import RxSwift
import UIKit
import XLActionController

class PanelMenuViewController: TweetbotActionController {
    private var disposeBag = DisposeBag()
    var tapTrigger: PublishRelay<Int> = .init() // タップされたらどの選択肢がおされたのか(=order)を流す
    
    override public init(nibName nibNameOrNil: String? = nil, bundle nibBundleOrNil: Bundle? = nil) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        
        // TweetbotActionControllerのonConfigureCellForActionを書き換えて色を変更する
        guard let onConfigureCellForAction = self.onConfigureCellForAction else { return }
        self.onConfigureCellForAction = { [weak self] cell, action, indexPath in
            onConfigureCellForAction(cell, action, indexPath)
            
            // color
            cell.backgroundColor = action.style == .cancel ? self?.getCancelColor() : self?.getMenuColor()
            cell.actionTitleLabel?.textColor = self?.getTextColor()
            
            // selected color
            let backgroundView = UIView()
            backgroundView.backgroundColor = self?.getSelectedColor()
            cell.selectedBackgroundView = backgroundView
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    // MARK: Publics
    
    /// メニューを追加
    /// - Parameter items: メニューアイテム
    func setupMenu(items: [MenuItem]) {
        setup()
        items.forEach { item in
            setItem(item)
        }
        setupCancelItem()
    }
    
    // MARK: Privates
    
    private func setup() {
        settings.animation.scale = CGSize(width: 1, height: 1)
    }
    
    private func setupCancelItem() {
        addSection(Section())
        addAction(Action("Cancel", style: .cancel, handler: nil))
    }
    
    private func setItem(_ item: MenuItem) {
        addAction(Action(item.title, style: .default, handler: { _ in
            self.tapTrigger.accept(item.order)
        }))
    }
    
    // MARK: Color
    
    private func getMenuColor() -> UIColor {
        guard let theme = Theme.shared.currentModel else { return .white }
        return theme.colorMode == .light ? theme.colorPattern.ui.base : theme.colorPattern.ui.sub2
    }
    
    private func getCancelColor() -> UIColor {
        guard let theme = Theme.shared.currentModel else { return .white }
        return theme.colorMode == .light ? theme.colorPattern.ui.sub2 : theme.colorPattern.ui.sub3
    }
    
    private func getSelectedColor() -> UIColor {
        var selectedColor: UIColor = .systemBlue
        if let mainColorHex = Theme.shared.currentModel?.mainColorHex {
            selectedColor = UIColor(hex: mainColorHex)
        }
        
        selectedColor = selectedColor.withAlphaComponent(0.6) // 明るすぎるのでalphaを微調整
        return selectedColor
    }
    
    private func getTextColor() -> UIColor {
        guard let theme = Theme.shared.currentModel else { return .black }
        return theme.colorPattern.ui.text
    }
}

extension PanelMenuViewController {
    struct MenuItem {
        let title: String
        let awesomeIcon: String
        
        var order: Int = 0
    }
}

// MARK: Legacy

class _PanelMenuViewController: UIViewController {
    @IBOutlet weak var panelTitleLabel: UILabel!
    @IBOutlet weak var stackView: UIStackView!
    @IBOutlet weak var stackViewHeightContraint: NSLayoutConstraint!
    
    private var panelTitle: String = ""
    private var itemViews: [UIView] = []
    
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
//    private func getMenuItemView(with item: MenuItem) -> UIView {
//        //        let theme = Theme.shared.getCurrentTheme()
//        let menuView = UIView()
//
//        menuView.layer.cornerRadius = 10
//        menuView.backgroundColor = .systemBlue
//
//        // label: アイコン
//        let iconLabel = UILabel()
//        iconLabel.text = item.awesomeIcon
//        iconLabel.font = .awesomeSolid(fontSize: 25.0)
//        iconLabel.textColor = .white
//        iconLabel.minimumScaleFactor = 0.1
//
//        iconLabel.sizeToFit()
//        iconLabel.isUserInteractionEnabled = true
//        iconLabel.translatesAutoresizingMaskIntoConstraints = false
//        menuView.addSubview(iconLabel)
//
//        // label: 選択肢のlabel
//        let titleLabel = UILabel()
//        titleLabel.text = item.title
//        titleLabel.font = .systemFont(ofSize: 20.0)
//        titleLabel.textColor = .white
//
//        titleLabel.sizeToFit()
//        titleLabel.isUserInteractionEnabled = true
//        titleLabel.translatesAutoresizingMaskIntoConstraints = false
//        menuView.addSubview(titleLabel)
//
//        // AutoLayout
//        menuView.addConstraints([
//            NSLayoutConstraint(item: iconLabel,
//                               attribute: .width,
//                               relatedBy: .equal,
//                               toItem: menuView,
//                               attribute: .width,
//                               multiplier: 0,
//                               constant: 50),
//
//            NSLayoutConstraint(item: iconLabel,
//                               attribute: .height,
//                               relatedBy: .equal,
//                               toItem: menuView,
//                               attribute: .height,
//                               multiplier: 0,
//                               constant: 30),
//
//            NSLayoutConstraint(item: iconLabel,
//                               attribute: .left,
//                               relatedBy: .equal,
//                               toItem: menuView,
//                               attribute: .left,
//                               multiplier: 1.0,
//                               constant: 20),
//
//            NSLayoutConstraint(item: iconLabel,
//                               attribute: .centerY,
//                               relatedBy: .equal,
//                               toItem: menuView,
//                               attribute: .centerY,
//                               multiplier: 1.0,
//                               constant: 0)
//        ])
//
//        menuView.addConstraints([
//            NSLayoutConstraint(item: titleLabel,
//                               attribute: .left,
//                               relatedBy: .equal,
//                               toItem: iconLabel,
//                               attribute: .left,
//                               multiplier: 1.0,
//                               constant: 40),
//
//            NSLayoutConstraint(item: titleLabel,
//                               attribute: .centerY,
//                               relatedBy: .equal,
//                               toItem: menuView,
//                               attribute: .centerY,
//                               multiplier: 1.0,
//                               constant: 0)
//        ])
//
    ////        setupTapGesture(to: menuView, tappedItem: item)
//        return menuView
//    }
}
