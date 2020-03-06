//
//  ReactionCell.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/14.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Gifu
import RxSwift
import UIKit

public protocol ReactionCellDelegate {
    func tappedReaction(noteId: String, reaction: String, isRegister: Bool) // isRegister: リアクションを「登録」するのか「取り消す」のか
}

public class ReactionCell: UICollectionViewCell {
    @IBOutlet weak var reactionCounterLabel: UILabel!
    @IBOutlet weak var defaultEmojiLabel: UILabel!
    @IBOutlet weak var customEmojiView: GIFImageView!
    
    private let disposeBag = DisposeBag()
    
    private let defaultBGColor = UIColor(hex: "C6C6C6")
    private let defaultTextColor = UIColor(hex: "666666")
    private var isMyReaction: Bool = false
    private var rawReaction: String?
    private var noteId: String?
    
    public var delegate: ReactionCellDelegate?
    
    // MARK: Life Cycle
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        changeColor(isMyReaction: isMyReaction)
    }
    
    // MARK: Setup
    
    private func addTapGesture(to view: UIView) {
        let tapGesture = UITapGestureRecognizer()
        
        // 各々のEmojiViewに対してtap gestureを付加する
        tapGesture.rx.event.bind { _ in
            self.isMyReaction = !self.isMyReaction
            
            UIView.animate(withDuration: 0.3,
                           animations: {
                               self.changeColor(isMyReaction: self.isMyReaction)
                               self.incrementCounter()
                           }, completion: { _ in
                               guard let delegate = self.delegate,
                                   let noteId = self.noteId,
                                   let rawReaction = self.rawReaction else { return }
                               
                               delegate.tappedReaction(noteId: noteId, reaction: rawReaction, isRegister: self.isMyReaction)
            })
        }.disposed(by: disposeBag)
        
        view.addGestureRecognizer(tapGesture)
    }
    
    public func setup(noteId: String?, count: String, defaultEmoji: String? = nil, customEmoji: String? = nil, rawDefaultEmoji: String? = nil, isMyReaction: Bool, rawReaction: String) {
        self.isMyReaction = isMyReaction
        self.rawReaction = rawReaction
        self.noteId = noteId ?? ""
        
        reactionCounterLabel.text = count
        
        if let defaultEmoji = defaultEmoji {
            defaultEmojiLabel.isHidden = false
            customEmojiView.isHidden = true
            
            defaultEmojiLabel.text = defaultEmoji
        } else if let customEmoji = customEmoji {
            defaultEmojiLabel.isHidden = true
            customEmojiView.isHidden = false
            
            customEmojiView.setImage(url: customEmoji)
        } else if let rawDefaultEmoji = rawDefaultEmoji {
            defaultEmojiLabel.isHidden = false
            customEmojiView.isHidden = true
            
            defaultEmojiLabel.text = rawDefaultEmoji
        }
    }
    
    public func setGradation(view: UIView) {
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [UIColor.darkGray.cgColor, UIColor.lightGray.cgColor]
        gradientLayer.frame.size = view.frame.size
        
        view.layer.addSublayer(gradientLayer)
        view.layer.masksToBounds = true
    }
    
    private func changeColor(isMyReaction: Bool) {
        backgroundColor = isMyReaction ? UIColor(hex: "EE7258") : defaultBGColor
        reactionCounterLabel.textColor = isMyReaction ? .white : defaultTextColor
    }
    
    private func incrementCounter() {
        guard let count = reactionCounterLabel.text else { return }
        reactionCounterLabel.text = count.increment()
    }
}
