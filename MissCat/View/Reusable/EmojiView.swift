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
        if let view = UINib(nibName: "EmojiView", bundle: Bundle(for: type(of: self))).instantiate(withOwner: self, options: nil)[0] as? UIView {
            view.frame = self.bounds
            self.addSubview(view)
        }
    }
    
    
    override func layoutSubviews() {
        super.layoutSubviews()
        self.setEmoji()
        self.adjustFontSize()
    }
    
    
    public func initialize() {
        self.isDefaultEmoji = true
        
        self.emojiLabel.text = nil
        self.emojiImageView.image = nil
        self.encodedEmoji = nil
        
        self.emojiLabel.isHidden = false
        self.emojiImageView.isHidden = false
    }
    
    //MARK: Emojis
    private func encodeEmoji(emoji rawEmoji: String)-> String {
        guard let convertedEmojiData = EmojiHandler.handler.convertEmoji(raw: rawEmoji) else { return rawEmoji }
        self.isDefaultEmoji = convertedEmojiData.type == "default"
        
        return convertedEmojiData.emoji
    }
    
    private func setEmoji() {
        guard let encodedEmoji = encodedEmoji else { return }
        
        if isDefaultEmoji {
            self.emojiLabel.text = encodedEmoji
            self.emojiImageView.isHidden = true
        }
        else {
            self.emojiLabel.isHidden = true
            encodedEmoji.toUIImage { image in
                DispatchQueue.main.async {
                    self.emojiImageView.image = image
                }
            }
        }
    }
    
    //MARK: Others
    private func adjustFontSize() {
        guard isDefaultEmoji, let encodedEmoji = encodedEmoji else { return }
        
        var labelWidth: CGFloat = 0
        var font: UIFont = self.emojiLabel.font ?? UIFont.systemFont(ofSize: 15.0)
        
        while self.frame.width - labelWidth >= 2 { // 最適なwidthとなるフォントサイズを探索する
            font = font.withSize(font.pointSize + 1)
            labelWidth = self.getLabelWidth(text: encodedEmoji, font: font)
        }
        
        self.emojiLabel.font = font
    }
    
}
