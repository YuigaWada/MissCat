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
    
    convenience init(with contents: NotificationModel, owner: SecureUser) {
        self.init()
        loadNib()
        setupComponents()
        viewModel = getViewModel(with: contents, owner: owner)
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
//        appear()
    }
    
    func loadNib() {
        if let view = UINib(nibName: "NotificationBanner", bundle: Bundle(for: type(of: self))).instantiate(withOwner: self, options: nil)[0] as? UIView {
            view.frame = bounds
            addSubview(view)
            initialize()
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
    
    private func getViewModel(with item: NotificationModel, owner: SecureUser) -> NotificationBannerViewModel? {
        guard let viewModel = NotificationBannerViewModel(with: item, and: disposeBag, owner: owner) else { return nil }
        
        binding(with: viewModel)
        viewModel.setCell()
        return viewModel
    }
    
    func initialize() {
        iconImageView.image = nil
        
        noteView.attributedText = nil
        typeIconView.text = nil
        typeLabel.text = nil
        
        nameTextView.attributedText = nil
        
        emojiView.isHidden = false
        emojiView.initialize()
    }
    
    private func setupComponents() {
        iconImageView.maskCircle()
        setTheme()
        
        noteView.delegate = self
        noteView.textColor = .lightGray
        
        typeIconView.font = .awesomeSolid(fontSize: 14.0)
        setupTimer()
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
    
    func setAutoLayout(on view: UIView, widthScale: CGFloat, heightScale: CGFloat, bottom: CGFloat) {
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
                               attribute: .bottom,
                               relatedBy: .equal,
                               toItem: view.safeAreaLayoutGuide,
                               attribute: .bottom,
                               multiplier: 1.0,
                               constant: -1 * bottom)
        ])
    }
    
    // MARK: Animation
    
    private func setupTimer() {
        _ = Timer.scheduledTimer(timeInterval: 5.0,
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
