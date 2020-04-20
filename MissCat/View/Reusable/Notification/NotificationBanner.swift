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
    
    // MARK: Life Cycle
    
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
    
    func loadNib() {
        if let view = UINib(nibName: "NotificationBanner", bundle: Bundle(for: type(of: self))).instantiate(withOwner: self, options: nil)[0] as? UIView {
            view.frame = bounds
            addSubview(view)
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        setupComponents()
        
        adjustFrame()
        setupCornerRadius()
        appear()
    }
    
    // MARK: Setup
    
    private func setupComponents() {
        iconLabel.font = .awesomeSolid(fontSize: 15.0)
        iconLabel.textColor = .white
        
        mainContentLabel.textColor = .white
        
        backgroundColor = .black
        alpha = 0
        
        // Message
        mainContentLabel.text = notification
        
        // Icon
        guard icon != .Loading else {
            addIndicator()
            return
        }
        
        guard icon != .Reaction else {
            guard let reaction = reaction else { return }
            
            let encodedReaction = EmojiHandler.handler.emojiEncoder(note: reaction, externalEmojis: nil)
            iconLabel.attributedText = encodedReaction.toAttributedString(family: "Helvetica", size: 15.0)
            return
        }
        
        iconLabel.text = icon.convertAwesome()
    }
    
    private func adjustFrame() {
        let contentLabelWidth = getLabelWidth(text: notification ?? "", font: UIFont.systemFont(ofSize: 12.0))
        let width = iconLabel.frame.width + contentLabelWidth + 20
        
        let dWidth = width - frame.width
        
        frame = CGRect(x: frame.origin.x - dWidth,
                       y: frame.origin.y,
                       width: width,
                       height: frame.height)
    }
    
    private func setupTimer() {
        _ = Timer.scheduledTimer(timeInterval: 2,
                                 target: self,
                                 selector: #selector(disappear),
                                 userInfo: nil,
                                 repeats: false)
    }
    
    private func setupCornerRadius() {
        layer.cornerRadius = 5
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer.masksToBounds = true
    }
    
    private func addIndicator() {
        let indicatorCenter = CGPoint(x: (mainContentLabel.frame.origin.x - 30) / 2,
                                      y: frame.height / 2)
        
        let activityIndicator = UIActivityIndicatorView()
        activityIndicator.center = indicatorCenter
        activityIndicator.hidesWhenStopped = true
        activityIndicator.style = UIActivityIndicatorView.Style.white
        
        addSubview(activityIndicator)
        activityIndicator.startAnimating()
        
        iconLabel.text = nil
    }
    
    // MARK: Appear / Disappear
    
    private func appear() {
        UIView.animate(withDuration: 1.3, animations: {
            self.alpha = 0.8
        })
    }
    
    @objc private func disappear() {
        UIView.animate(withDuration: 1.3, animations: {
            self.alpha = 0
        }, completion: { _ in
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
        
        func convertAwesome() -> String {
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
