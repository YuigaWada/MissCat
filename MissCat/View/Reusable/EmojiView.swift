//
//  EmojiView.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/18.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit

class EmojiView: UIView {
    @IBOutlet weak var emojiLabel: UILabel!
    @IBOutlet weak var emojiImageView: UIImageView!
    @IBOutlet var view: UIView!
    
    private var isDefaultEmoji: Bool = true
    private var encodedEmoji: String?
    
    public var emoji: String = "👍" {
        didSet {
            self.encodedEmoji = self.encodeEmoji(emoji: self.emoji)
            self.setEmoji()
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
        if let view = UINib(nibName: "EmojiView", bundle: Bundle(for: type(of: self))).instantiate(withOwner: self, options: nil)[0] as? UIView {
            view.frame = bounds
            addSubview(view)
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        setEmoji()
        adjustFontSize()
    }
    
    public func initialize() {
        isDefaultEmoji = true
        
        emojiLabel.text = nil
        emojiImageView.image = nil
        encodedEmoji = nil
        
        emojiLabel.isHidden = false
        emojiImageView.isHidden = false
    }
    
    // MARK: Emojis
    
    private func encodeEmoji(emoji rawEmoji: String) -> String {
        guard let convertedEmojiData = EmojiHandler.handler.convertEmoji(raw: rawEmoji) else { return rawEmoji }
        isDefaultEmoji = convertedEmojiData.type == "default"
        
        return convertedEmojiData.emoji
    }
    
    private func setEmoji() {
        guard let encodedEmoji = encodedEmoji else { return }
        
        if isDefaultEmoji {
            emojiLabel.text = encodedEmoji
            emojiImageView.isHidden = true
        } else {
            emojiLabel.isHidden = true
            encodedEmoji.toUIImage { image in
                DispatchQueue.main.async {
                    self.emojiImageView.image = image
                }
            }
        }
    }
    
    // MARK: Others
    
    private func adjustFontSize() {
        guard isDefaultEmoji, let encodedEmoji = encodedEmoji else { return }
        
        var labelWidth: CGFloat = 0
        var font: UIFont = emojiLabel.font ?? UIFont.systemFont(ofSize: 15.0)
        
        while frame.width - labelWidth >= 2 { // 最適なwidthとなるフォントサイズを探索する
            font = font.withSize(font.pointSize + 1)
            labelWidth = getLabelWidth(text: encodedEmoji, font: font)
        }
        
        emojiLabel.font = font
    }
}
