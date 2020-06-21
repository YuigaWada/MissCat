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
    func changeUser(_ user: SecureUser)
    func showAccountMenu(sourceRect: CGRect) -> Observable<SecureUser>?
    func tappedRightNavButton()
}

class NavBar: UIView {
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var userIconView: MissCatImageView!
    @IBOutlet weak var rightButton: UIButton!
    @IBOutlet weak var separator: UIView!
    
    private var viewModel: NavBarViewModel?
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
        
        let viewModel = setViewModel()
        binding(with: viewModel)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
        loadNib()
        
        let viewModel = setViewModel()
        binding(with: viewModel)
    }
    
    private func loadNib() {
        if let view = UINib(nibName: "NavBar", bundle: Bundle(for: type(of: self))).instantiate(withOwner: self, options: nil)[0] as? UIView {
            view.frame = bounds
            view.backgroundColor = .clear
            addSubview(view)
        }
    }
    
    private func setViewModel() -> NavBarViewModel {
        let viewModel = NavBarViewModel(with: nil, and: disposeBag)
        self.viewModel = viewModel
        return viewModel
    }
    
    private func binding(with viewModel: NavBarViewModel) {
        let output = viewModel.output
        output.userIcon.bind(to: userIconView.rx.image).disposed(by: disposeBag)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        guard !initialized else { return }
        setupGesture()
        bindTheme()
        setTheme()
        userIconView.maskCircle()
        
        initialized = true
    }
    
    // MARK: Design
    
    private func bindTheme() {
        let theme = Theme.shared.theme
        
        theme.map { $0.colorPattern.ui }.subscribe(onNext: { colorPattern in
            self.backgroundColor = colorPattern.base
            self.titleLabel.textColor = colorPattern.text
            self.separator.backgroundColor = colorPattern.sub2
        }).disposed(by: disposeBag)
    }
    
    private func setTheme() {
        if let colorPattern = Theme.shared.currentModel?.colorPattern.ui {
            backgroundColor = colorPattern.base
            titleLabel.textColor = colorPattern.text
            separator.backgroundColor = colorPattern.sub2
        }
    }
    
    // Public Methods
    
    /// NavBarのスタイルを設定する
    func setButton(style: NavBar.Button, needIcon: Bool = true, rightText: String? = nil, leftText: String? = nil, rightFont: UIFont? = nil, leftFont: UIFont? = nil) {
        // Image
        setUserIcon()
        userIconView.isHidden = !needIcon
        
        // isHidden
        rightButton.isHidden = false
        
        switch style {
        case .Both:
            break
            
        case .Right:
            break
            
        case .Left:
            rightButton.isHidden = true
            
        case .None:
            rightButton.isHidden = true
            
            return
        }
        
        // Text
        rightButton.setTitle(rightText, for: .normal)
        
        // Font
        if let rightFont = rightFont {
            rightButton.titleLabel?.font = rightFont
        }
    }
    
    private func setupGesture() {
        userIconView.setTapGesture(disposeBag, closure: {
            self.showAccountsMenu()
        })
        
        rightButton.rx.tap.subscribe { _ in
            guard let delegate = self.delegate else { return }
            delegate.tappedRightNavButton()
        }.disposed(by: disposeBag)
    }
    
    /// ユーザーアイコンを設定
    private func setUserIcon(of user: SecureUser) {
        userIconView.isHidden = false
        viewModel?.transform(user: user)
    }
    
    /// ユーザーアイコンを設定
    private func setUserIcon() {
        guard let user = Cache.UserDefaults.shared.getCurrentUser() else {
            userIconView.image = nil
            userIconView.isHidden = true
            return
        }
        setUserIcon(of: user)
    }
    
    /// アカウントメニューを表示する
    private func showAccountsMenu() {
        let selected = delegate?.showAccountMenu(sourceRect: userIconView.frame)
        
        selected?.subscribe(onNext: { user in
            self.setUserIcon(of: user)
            Cache.UserDefaults.shared.changeCurrentUser(userId: user.userId)
            self.delegate?.changeUser(user)
        }).disposed(by: disposeBag)
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
