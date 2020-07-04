//
//  NotificationBanner.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/12/22.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxCocoa
import RxSwift
import UIKit

// Data
struct NotificationData {
    let ownerId: String
    let notificationId: String
}

// Banner

class NotificationBanner: UIView, UITextViewDelegate {
    @IBOutlet weak var iconImageView: MissCatImageView!
    
    @IBOutlet weak var nameTextView: MisskeyTextView!
    @IBOutlet weak var noteView: MisskeyTextView!
    
    @IBOutlet weak var typeIconView: UILabel!
    @IBOutlet weak var typeLabel: UILabel!
    
    private lazy var emojiView = self.generateEmojiView()
    
    private var contents: NotificationData?
    
    private var viewModel: NotificationBannerViewModel?
    private let disposeBag: DisposeBag = .init()
    
    // MARK: LifeCycle
    
    convenience init(with contents: NotificationModel) {
        self.init()
        loadNib()
        setupComponents()
        viewModel = getViewModel(with: contents)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        loadNib()
        setupComponents()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadNib()
        setupComponents()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        nameTextView.transformText()
    }
    
    func loadNib() {
        if let view = UINib(nibName: "NotificationBanner", bundle: Bundle(for: type(of: self))).instantiate(withOwner: self, options: nil)[0] as? UIView {
            view.frame = bounds
            addSubview(view)
        }
    }
    
    // MARK: Theme
    
    private func bindTheme() {
        let theme = Theme.shared.theme
        
        theme.map { UIColor(hex: $0.mainColorHex) }.subscribe(onNext: { _ in
            
        }).disposed(by: disposeBag)
    }
    
    private func setTheme() {
//        if let mainColorHex = Theme.shared.currentModel?.mainColorHex {
//            mainColor = UIColor(hex: mainColorHex)
//        }
        if let colorPattern = Theme.shared.currentModel?.colorPattern.ui {
            backgroundColor = colorPattern.base
            typeLabel.textColor = colorPattern.text
        }
    }
    
    // MARK: Setup
    
    private func getViewModel(with item: NotificationModel) -> NotificationBannerViewModel? {
        guard let viewModel = NotificationBannerViewModel(with: item, and: disposeBag) else { return nil }
        
        binding(with: viewModel)
        viewModel.setCell()
        return viewModel
    }
    
    private func setupComponents() {
        iconImageView.maskCircle()
        setTheme()
        
        noteView.delegate = self
        noteView.textColor = .lightGray
        
        typeIconView.font = .awesomeSolid(fontSize: 14.0)
    }
    
    // MARK: Binding
    
    private func binding(with viewModel: NotificationBannerViewModel) {
        let output = viewModel.output
        
        // meta
        output.name
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: { nameMfmString in
                self.nameTextView.attributedText = nameMfmString.attributed
                nameMfmString.mfmEngine.renderCustomEmojis(on: self.nameTextView)
            }).disposed(by: disposeBag)
        
        output.note
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: { noteMfmString in
                self.noteView.attributedText = noteMfmString.attributed
                noteMfmString.mfmEngine.renderCustomEmojis(on: self.noteView)
            }).disposed(by: disposeBag)
        
        output.iconImage
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(iconImageView.rx.image)
            .disposed(by: disposeBag)
        
        // color
        
        output.textColor
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: { self.typeLabel.textColor = $0 })
            .disposed(by: disposeBag)
        
        output.backgroundColor
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(rx.backgroundColor)
            .disposed(by: disposeBag)
        
        // emoji
        output.needEmoji
            .map { !$0 }
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(emojiView.rx.isHidden)
            .disposed(by: disposeBag)
        
        output.emoji
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: { self.emojiView.emoji = $0 })
            .disposed(by: disposeBag)
        
        // response
        output.typeString
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(typeLabel.rx.text)
            .disposed(by: disposeBag)
        
        output.typeIconColor
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: { self.typeIconView.textColor = $0 })
            .disposed(by: disposeBag)
        
        output.typeIconString
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(typeIconView.rx.text)
            .disposed(by: disposeBag)
    }
    
    // MARK: View
    
    private func generateEmojiView() -> EmojiView {
        let emojiView = EmojiView()
        
        let sqrt2 = 1.41421356237
        let cos45 = CGFloat(sqrt2 / 2)
        
        let r = iconImageView.frame.width / 2
        let emojiViewRadius = 2 / 3 * r
        
        let basePosition = iconImageView.frame.origin
        let position = CGPoint(x: basePosition.x + cos45 * r,
                               y: basePosition.y + cos45 * r)
        
        emojiView.frame = CGRect(x: position.x,
                                 y: position.y,
                                 width: emojiViewRadius * 2,
                                 height: emojiViewRadius * 2)
        
        emojiView.view.layer.backgroundColor = UIColor(hex: "EE7258").cgColor
        emojiView.view.layer.cornerRadius = emojiViewRadius
        
        return emojiView
    }
    
    // MARK: AutoLayout
    
    func setAutoLayout(on view: UIView, widthScale: CGFloat, heightScale: CGFloat, originY: CGFloat) {
        view.addConstraints([
            NSLayoutConstraint(item: self,
                               attribute: .width,
                               relatedBy: .equal,
                               toItem: view,
                               attribute: .width,
                               multiplier: widthScale,
                               constant: 0),
            
            NSLayoutConstraint(item: self,
                               attribute: .height,
                               relatedBy: .equal,
                               toItem: view,
                               attribute: .height,
                               multiplier: heightScale,
                               constant: 0),
            
            NSLayoutConstraint(item: self,
                               attribute: .centerX,
                               relatedBy: .equal,
                               toItem: view,
                               attribute: .centerX,
                               multiplier: 1.0,
                               constant: 0),
            
            NSLayoutConstraint(item: self,
                               attribute: .top,
                               relatedBy: .equal,
                               toItem: view,
                               attribute: .top,
                               multiplier: 1.0,
                               constant: originY)
        ])
    }
    
    // MARK: Animation
    
    private func setupTimer() {
        _ = Timer.scheduledTimer(timeInterval: 2,
                                 target: self,
                                 selector: #selector(disappear),
                                 userInfo: nil,
                                 repeats: false)
    }
    
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

// 小さい通知バナー
class NanoNotificationBanner: UIView {
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
        if let view = UINib(nibName: "NanoNotificationBanner", bundle: Bundle(for: type(of: self))).instantiate(withOwner: self, options: nil)[0] as? UIView {
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
        
        //        guard icon != .Reaction else {
        //            guard let reaction = reaction else { return }
        //
        //            let encodedReaction = EmojiHandler.handler.emojiEncoder(note: reaction, externalEmojis: nil)
        //            iconLabel.attributedText = encodedReaction.toAttributedString(family: "Helvetica", size: 15.0)
        //            return
        //        }
        
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

extension NanoNotificationBanner {
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
