//
//  NavBar.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/25.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import RxSwift
import UIKit

public protocol NavBarDelegate {
    func tappedLeftNavButton()
    func tappedRightNavButton()
}

public class NavBar: UIView {
    @IBOutlet weak var titleLabel: UILabel!
    
    @IBOutlet weak var leftButton: UIButton!
    @IBOutlet weak var rightButton: UIButton!
    
    private let disposeBag = DisposeBag()
    
    public var delegate: NavBarDelegate?
    public var barTitle: String? {
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
    
    public func loadNib() {
        if let view = UINib(nibName: "NavBar", bundle: Bundle(for: type(of: self))).instantiate(withOwner: self, options: nil)[0] as? UIView {
            view.frame = bounds
            addSubview(view)
        }
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        setupGesture()
    }
    
    // Public Methods
    public func setButton(style: NavBar.Button, rightText: String? = nil, leftText: String? = nil, rightFont: UIFont? = nil, leftFont: UIFont? = nil) {
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
    public enum Button {
        case Right
        case Left
        case Both
        case None
    }
}
