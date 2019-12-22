//
//  NotificationBanner.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/12/22.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit

class NotificationBanner: UIView {
    @IBOutlet weak var iconLabel: UILabel!
    @IBOutlet weak var mainContentLabel: UILabel!
    
    private var icon: IconType = .Failed
    private var reaction: String?
    private var notification: String?
    
    
    //MARK: Life Cycle
    init(frame: CGRect, icon: IconType, reaction: String? = nil, notification: String) {
        super.init(frame: frame)
        
        self.icon = icon
        self.reaction = reaction
        self.notification = notification
        
        loadNib()
        setupTimer()
    }
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        loadNib()
        setupTimer()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
        loadNib()
        setupTimer()
    }
    
    public func loadNib() {
        if let view = UINib(nibName: "NotificationBanner", bundle: Bundle(for: type(of: self))).instantiate(withOwner: self, options: nil)[0] as? UIView {
            view.frame = self.bounds
            self.addSubview(view)
        }
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        self.setupComponents()
        
        self.adjustFrame()
        self.setupCornerRadius()
        self.appear()
    }
    
    
    
    //MARK: Setup
    private func setupComponents() {
        self.iconLabel.font = .awesomeSolid(fontSize: 15.0)
        self.iconLabel.textColor = .white
        
        self.mainContentLabel.textColor = .white
        
        self.backgroundColor = .black
        self.alpha = 0
        
        // Message
        self.mainContentLabel.text = notification
        
        // Icon
        guard icon != .Loading else {
            self.addIndicator()
            return
        }
        
        
        guard icon != .Reaction else {
            guard let reaction = reaction else { return }
            
            let encodedReaction = EmojiHandler.handler.emojiEncoder(note: reaction, externalEmojis: nil)
            self.iconLabel.attributedText = encodedReaction.toAttributedString(family: "Helvetica", size: 15.0)
            return
        }
        
        
        self.iconLabel.text = icon.convertAwesome()
    }
    
    private func adjustFrame() {
        let contentLabelWidth = self.getLabelWidth(text: notification ?? "", font: UIFont.systemFont(ofSize: 12.0))
        let width = iconLabel.frame.width + contentLabelWidth + 20
        
        let dWidth = width - self.frame.width
        
        self.frame = CGRect(x: self.frame.origin.x - dWidth,
                            y: self.frame.origin.y,
                            width: width,
                            height: self.frame.height)
    }
    
    private func setupTimer() {
        let _ = Timer.scheduledTimer(timeInterval: 2,
                                     target: self,
                                     selector: #selector(self.disappear),
                                     userInfo: nil,
                                     repeats: false)
    }
    
    
    private func setupCornerRadius() {
        self.layer.cornerRadius = 5
        self.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        self.layer.masksToBounds = true
    }
    
    private func addIndicator() {
        let indicatorCenter = CGPoint(x: (self.mainContentLabel.frame.origin.x - 30) / 2,
                                      y: self.frame.height / 2)
        
        let activityIndicator = UIActivityIndicatorView()
        activityIndicator.center = indicatorCenter
        activityIndicator.hidesWhenStopped = true
        activityIndicator.style = UIActivityIndicatorView.Style.white
        
        self.addSubview(activityIndicator)
        activityIndicator.startAnimating()
        
        self.iconLabel.text = nil
    }
    
    
    
    //MARK: Appear / Disappear
    private func appear() {
        UIView.animate(withDuration: 1.3, animations: {
            self.alpha = 0.8
        })
    }
    
    @objc private func disappear() {
        UIView.animate(withDuration: 1.3, animations: {
            self.alpha = 0
        },completion: { _ in
            self.removeFromSuperview()
        })
    }
    
}


extension NotificationBanner {
    enum IconType {
        case Loading
        case Success
        
        case Reply
        case Renote
        case Reaction
        
        case Failed
        case Warning
        
        func convertAwesome()-> String {
            switch self {
            case .Loading:
                return ""
            case .Success:
                return "check-circle"
            case .Reply:
                return "reply"
            case .Renote:
                return "retweet"
            case .Reaction:
                return ""
            case .Failed:
                return "times-circle"
            case .Warning:
                return "exclamation-triangle"
            }
        }
    }
}
