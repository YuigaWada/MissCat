//
//  TabBar.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/16.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit

public enum TabKind {
    case home
    case notifications
    case fav
    case profile
}

public protocol FooterTabBarDelegate {
    
    var storyboard: UIStoryboard? { get }
    
    func tappedHome()
    func tappedNotifications()
    func tappedPost()
    func tappedFav()
    func tappedProfile()
    
    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)?)
    func dismiss(animated flag: Bool, completion: (() -> Void)?)
}





public class FooterTabBar: UIView {
    
    @IBOutlet weak var homeButton: UIButton!
    @IBOutlet weak var notificationButton: UIButton!
    @IBOutlet weak var postButton: UIButton!
    @IBOutlet weak var favButton: UIButton!
    @IBOutlet weak var profileButton: UIButton!
    
    @IBOutlet weak var postBottonFrame: UIView!
    
    public var delegate: FooterTabBarDelegate?
    public var selected: TabKind = .home {
        willSet(new) {
            self.lightupButton(old: selected, new)
        }
    }
    
    
    
    //MARK: Life Cycle
    override init(frame: CGRect) {
        super.init(frame: frame)
        loadNib()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
        loadNib()
    }
    
    public func loadNib() {
        if let view = UINib(nibName: "TabBar", bundle: Bundle(for: type(of: self))).instantiate(withOwner: self, options: nil)[0] as? UIView {
            view.frame = self.bounds
            self.addSubview(view)
        }
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        self.setupComponents()
    }
    
    public override func draw(_ rect: CGRect) {
        super.draw(rect)
        self.postBottonFrame.layer.cornerRadius = self.postBottonFrame.frame.height / 2
    }
    
    //MARK: Setup
    
    public func setupComponents() {
        let fontSize: CGFloat = 20.0
        
        self.homeButton.titleLabel?.font = .awesomeSolid(fontSize: fontSize)
        self.notificationButton.titleLabel?.font = .awesomeSolid(fontSize: fontSize)
        self.postButton.titleLabel?.font = .awesomeRegular(fontSize: fontSize)
        self.favButton.titleLabel?.font = .awesomeSolid(fontSize: fontSize)
        self.profileButton.titleLabel?.font = .awesomeSolid(fontSize: fontSize)
    }
    
    
    //MARK: IBAction
    @IBAction func tappedHome(_ sender: Any) {
        guard let delegate = delegate else { return }
        
        self.selected = .home
        self.dismiss()
        delegate.tappedHome()
    }
    
    @IBAction func tappedNotifications(_ sender: Any) {
        guard let delegate = delegate else { return }
        
        self.selected = .notifications
        delegate.tappedNotifications()
    }
    
    @IBAction func tappedPost(_ sender: Any) {
        guard let delegate = delegate else { return }
        delegate.tappedPost()
    }
    
    @IBAction func tappedFav(_ sender: Any) {
        guard self.selected != .fav else { return }
        self.selected = .fav
    }
    
    @IBAction func tappedUser(_ sender: Any) {
        guard let delegate = delegate else { return }

        self.selected = .profile
        delegate.tappedProfile()
    }
    
    
    
    
    //MARK: Utilities
    private func dismiss() {
        guard let delegate = delegate else { return }
        
        delegate.dismiss(animated: true, completion: nil)
    }
    
    
    private func lightupButton(old: TabKind, _ new: TabKind) {
        self.changeButtonColor(target: old, color: .lightGray)
        self.changeButtonColor(target: new, color: .systemBlue)
    }
    
    private func changeButtonColor(target: TabKind, color: UIColor) {
        
        switch target {
        case .home:
            self.homeButton.setTitleColor(color, for: .normal)
        case .notifications:
            self.notificationButton.setTitleColor(color, for: .normal)
        case .fav:
            self.favButton.setTitleColor(color, for: .normal)
        case .profile:
            self.profileButton.setTitleColor(color, for: .normal)
        }
        
    }
    
    
}
