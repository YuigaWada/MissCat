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

protocol ReactionCellDelegate {
    func tappedReaction(noteId: String, reaction: String, isRegister: Bool) // isRegister: リアクションを「登録」するのか「取り消す」のか
}

class ReactionCell: UICollectionViewCell, ComponentType {
    typealias Arg = NoteCell.Reaction
    typealias Transformed = ReactionCell
    
    @IBOutlet weak var reactionCounterLabel: UILabel!
    @IBOutlet weak var defaultEmojiLabel: UILabel!
    
    @IBOutlet weak var customEmojiView: MFMImageView!
    
    private let disposeBag = DisposeBag()
    
    var selectedBackGroundColor = UIColor(hex: "DF785F")
    var nonselectedBackGroundColor: UIColor
    
    var selectedTextColor = UIColor.white
    var nonselectedTextColor = UIColor.white
    
    private var isMyReaction: Bool = false
    private var rawReaction: String?
    private var noteId: String?
    
    var delegate: ReactionCellDelegate?
    
    // MARK: Life Cycle
    
    override init(frame: CGRect) {
        nonselectedBackGroundColor = Theme.shared.currentModel?.colorPattern.ui.sub3 ?? UIColor(hex: "C6C6C6")
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        nonselectedBackGroundColor = Theme.shared.currentModel?.colorPattern.ui.sub3 ?? UIColor(hex: "C6C6C6")
        super.init(coder: coder)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        changeColor(isMyReaction: isMyReaction)
    }
    
    // MARK: Publics
    
    func transform(with arg: NoteCell.Reaction) -> ReactionCell {
        let item = arg
        guard let rawEmoji = item.entity.rawEmoji else { return self }
        
        if let customEmojiUrl = item.entity.url {
            setup(noteId: item.entity.noteId,
                  count: item.entity.count,
                  customEmoji: customEmojiUrl,
                  isMyReaction: item.entity.isMyReaction,
                  rawReaction: rawEmoji)
        } else {
            setup(noteId: item.entity.noteId,
                  count: item.entity.count,
                  rawDefaultEmoji: rawEmoji,
                  isMyReaction: item.entity.isMyReaction,
                  rawReaction: rawEmoji)
        }
        
        return self
    }
    
    // MARK: Setup
    
    private func setup(noteId: String?, count: String, defaultEmoji: String? = nil, customEmoji: String? = nil, rawDefaultEmoji: String? = nil, isMyReaction: Bool, rawReaction: String) {
        self.isMyReaction = isMyReaction
        self.rawReaction = rawReaction
        self.noteId = noteId ?? ""
        alpha = 1
        
        addTapGesture(to: self)
        reactionCounterLabel.text = count
        if let defaultEmoji = defaultEmoji {
            defaultEmojiLabel.isHidden = false
            customEmojiView.isHidden = true
            
            defaultEmojiLabel.text = defaultEmoji
        } else if let customEmoji = customEmoji {
            defaultEmojiLabel.isHidden = true
            customEmojiView.isHidden = false
            
            customEmojiView.image = nil
            customEmojiView.prepareForReuse()
            customEmojiView.setImage(url: customEmoji)
        } else if let rawDefaultEmoji = rawDefaultEmoji {
            defaultEmojiLabel.isHidden = false
            customEmojiView.isHidden = true
            
            defaultEmojiLabel.text = rawDefaultEmoji
        }
    }
    
    private func addTapGesture(to view: UIView) {
        let tapGesture = UITapGestureRecognizer()
        
        // 各々のEmojiViewに対してtap gestureを付加する
        tapGesture.rx.event.bind { _ in
            self.isMyReaction = !self.isMyReaction
            
            UIView.animate(withDuration: 0.3,
                           animations: {
                               self.changeColor(isMyReaction: self.isMyReaction)
                               self.changeCounter(plus: self.isMyReaction)
                           }, completion: { _ in
                               guard let delegate = self.delegate,
                                     let noteId = self.noteId,
                                     let rawReaction = self.rawReaction else { return }
                               
                               delegate.tappedReaction(noteId: noteId, reaction: rawReaction, isRegister: self.isMyReaction)
                               
                           })
        }.disposed(by: disposeBag)
        
        view.addGestureRecognizer(tapGesture)
    }
    
    func setGradation(view: UIView) {
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [UIColor.darkGray.cgColor, UIColor.lightGray.cgColor]
        gradientLayer.frame.size = view.frame.size
        
        view.layer.addSublayer(gradientLayer)
        view.layer.masksToBounds = true
    }
    
    /// 色の変更をUIに反映させる
    func updateColor() {
        changeColor(isMyReaction: isMyReaction)
    }
    
    private func changeColor(isMyReaction: Bool) {
        backgroundColor = isMyReaction ? selectedBackGroundColor : nonselectedBackGroundColor
        reactionCounterLabel.textColor = isMyReaction ? selectedTextColor : nonselectedTextColor
    }
    
    private func changeCounter(plus: Bool) {
        guard let count = reactionCounterLabel.text else { return }
        if plus {
            reactionCounterLabel.text = count.increment()
        } else {
            let newCount = count.decrement()
            guard newCount != "0" else { alpha = 0; return } // 1→0の場合はセルを削除
            reactionCounterLabel.text = newCount
        }
    }
}
