//
//  TabBar.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/16.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import RxCocoa
import RxSwift
import UIKit

enum TabKind {
    case home
    case notifications
    case messages
    case profile
}

protocol FooterTabBarDelegate {
    var storyboard: UIStoryboard? { get }
    
    func tappedHome()
    func tappedNotifications()
    func tappedPost()
    func tappedDM()
    func tappedProfile()
    
    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)?)
    func dismiss(animated flag: Bool, completion: (() -> Void)?)
}

class FooterTabBar: UIView {
    @IBOutlet weak var homeButton: UIButton!
    @IBOutlet weak var notificationButton: UIButton!
    @IBOutlet weak var postButton: UIButton!
    @IBOutlet weak var favButton: UIButton!
    @IBOutlet weak var profileButton: UIButton!
    
    @IBOutlet weak var postBottonFrame: UIView!
    
    private var disposeBag: DisposeBag
    private var offColor: UIColor = .lightGray
    private var onColor: UIColor = .systemBlue
    
    var delegate: FooterTabBarDelegate?
    var selected: TabKind = .home {
        didSet {
            self.changeSelectState(to: selected)
        }
    }
    
    // MARK: Life Cycle
    
    convenience init(with disposeBag: DisposeBag) {
        self.init()
        self.disposeBag = disposeBag
        setup()
    }
    
    override init(frame: CGRect) {
        disposeBag = .init()
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder aDecoder: NSCoder) {
        disposeBag = .init()
        super.init(coder: aDecoder)!
        setup()
    }
    
    private func setup() {
        loadNib()
        bindTheme()
        setTheme()
    }
    
    private func loadNib() {
        if let view = UINib(nibName: "TabBar", bundle: Bundle(for: type(of: self))).instantiate(withOwner: self, options: nil)[0] as? UIView {
            view.frame = bounds
            addSubview(view)
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        setupComponents()
    }
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        postBottonFrame.layer.cornerRadius = postBottonFrame.frame.height / 2
    }
    
    // MARK: Setup
    
    func setupComponents() {
        let fontSize: CGFloat = 20.0
        
        homeButton.titleLabel?.font = .awesomeSolid(fontSize: fontSize)
        notificationButton.titleLabel?.font = .awesomeSolid(fontSize: fontSize)
        postButton.titleLabel?.font = .awesomeRegular(fontSize: fontSize)
        favButton.titleLabel?.font = .awesomeSolid(fontSize: fontSize)
        profileButton.titleLabel?.font = .awesomeSolid(fontSize: fontSize)
    }
    
    private func bindTheme() {
        let theme = Theme.shared.theme
        
        theme.map { UIColor(hex: $0.mainColorHex) }.subscribe(onNext: { color in
            self.onColor = color
            self.postBottonFrame.backgroundColor = color
            self.changeSelectState(to: self.selected)
        }).disposed(by: disposeBag)
    }
    
    private func setTheme() {
        if let mainColorHex = Theme.shared.currentModel?.mainColorHex {
            let mainColor = UIColor(hex: mainColorHex)
            onColor = mainColor
            postBottonFrame.backgroundColor = mainColor
        }
    }
    
    // MARK: IBAction
    
    @IBAction func tappedHome(_ sender: Any) {
        guard let delegate = delegate else { return }
        
        selected = .home
        dismiss()
        delegate.tappedHome()
    }
    
    @IBAction func tappedNotifications(_ sender: Any) {
        guard let delegate = delegate else { return }
        
        selected = .notifications
        delegate.tappedNotifications()
    }
    
    @IBAction func tappedPost(_ sender: Any) {
        guard let delegate = delegate else { return }
        delegate.tappedPost()
    }
    
    @IBAction func tappedFav(_ sender: Any) {
        guard let delegate = delegate else { return }
        
        selected = .messages
        delegate.tappedDM()
    }
    
    @IBAction func tappedUser(_ sender: Any) {
        guard let delegate = delegate else { return }
        
        selected = .profile
        delegate.tappedProfile()
    }
    
    // MARK: Utilities
    
    private func dismiss() {
        guard let delegate = delegate else { return }
        
        delegate.dismiss(animated: true, completion: nil)
    }
    
    private func changeSelectState(to new: TabKind) {
        changeButtonColor(target: new, color: onColor)
        if new != .home {
            changeButtonColor(target: .home, color: offColor)
        }
        
        if new != .notifications {
            changeButtonColor(target: .notifications, color: offColor)
        }
        
        if new != .messages {
            changeButtonColor(target: .messages, color: offColor)
        }
        
        if new != .profile {
            changeButtonColor(target: .profile, color: offColor)
        }
    }
    
    private func changeButtonColor(target: TabKind, color: UIColor) {
        switch target {
        case .home:
            homeButton.setTitleColor(color, for: .normal)
        case .notifications:
            notificationButton.setTitleColor(color, for: .normal)
        case .messages:
            favButton.setTitleColor(color, for: .normal)
        case .profile:
            profileButton.setTitleColor(color, for: .normal)
        }
    }
}
