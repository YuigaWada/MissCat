//
//  NavBar.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/25.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import RxSwift
import UIKit

protocol NavBarDelegate {
    func tappedLeftNavButton()
    func tappedRightNavButton()
}

class NavBar: UIView {
    @IBOutlet weak var titleLabel: UILabel!
    
    @IBOutlet weak var leftButton: UIButton!
    @IBOutlet weak var rightButton: UIButton!
    
    private let disposeBag = DisposeBag()
    
    private var initialized: Bool = false
    var delegate: NavBarDelegate?
    var barTitle: String? {
        didSet {
            self.titleLabel.text = self.barTitle
        }
    }
    
    // MARK: Life Cycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        loadNib()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
        loadNib()
    }
    
    func loadNib() {
        if let view = UINib(nibName: "NavBar", bundle: Bundle(for: type(of: self))).instantiate(withOwner: self, options: nil)[0] as? UIView {
            view.frame = bounds
            view.backgroundColor = .clear
            addSubview(view)
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        guard !initialized else { return }
        setupGesture()
        bindTheme()
        setTheme()
        
        initialized = true
    }
    
    // MARK: Design
    
    private func bindTheme() {
        let theme = Theme.shared.theme
        
        theme.map { $0.colorPattern.ui }.subscribe(onNext: { colorPattern in
            self.backgroundColor = colorPattern.base
            self.titleLabel.textColor = colorPattern.text
        }).disposed(by: disposeBag)
    }
    
    private func setTheme() {
        if let colorPattern = Theme.shared.currentModel?.colorPattern.ui {
            backgroundColor = colorPattern.base
            titleLabel.textColor = colorPattern.text
        }
    }
    
    // Public Methods
    func setButton(style: NavBar.Button, rightText: String? = nil, leftText: String? = nil, rightFont: UIFont? = nil, leftFont: UIFont? = nil) {
        // isHidden
        rightButton.isHidden = false
        leftButton.isHidden = false
        
        switch style {
        case .Both:
            break
            
        case .Right:
            leftButton.isHidden = true
            
        case .Left:
            rightButton.isHidden = true
            
        case .None:
            leftButton.isHidden = true
            rightButton.isHidden = true
            
            return
        }
        
        // Text
        rightButton.setTitle(rightText, for: .normal)
        leftButton.setTitle(leftText, for: .normal)
        
        // Font
        if let rightFont = rightFont {
            rightButton.titleLabel?.font = rightFont
        }
        
        if let leftFont = leftFont {
            leftButton.titleLabel?.font = leftFont
        }
    }
    
    private func setupGesture() {
        leftButton.rx.tap.subscribe { _ in
            guard let delegate = self.delegate else { return }
            delegate.tappedLeftNavButton()
        }.disposed(by: disposeBag)
        
        rightButton.rx.tap.subscribe { _ in
            guard let delegate = self.delegate else { return }
            delegate.tappedRightNavButton()
        }.disposed(by: disposeBag)
    }
}

extension NavBar {
    enum Button {
        case Right
        case Left
        case Both
        case None
    }
}
