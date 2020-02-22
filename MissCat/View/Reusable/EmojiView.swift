//
//  EmojiView.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/18.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit

public class EmojiView: UIView {
    @IBOutlet weak var emojiLabel: UILabel!
    @IBOutlet weak var emojiImageView: UIImageView!
    @IBOutlet var view: UIView!
    
    public var emoji: EmojiView.EmojiModel?
    
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
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        setEmoji()
        adjustFontSize()
    }
    
    public func initialize() {
        emojiLabel.text = nil
        emojiImageView.image = nil
        
        emojiLabel.isHidden = false
        emojiImageView.isHidden = false
    }
    
    // MARK: Emojis
    
    private func setEmoji() {
        guard let emoji = emoji else { return }
        
        if emoji.isDefault {
            emojiLabel.text = emoji.defaultEmoji
            emojiImageView.isHidden = true
        } else {
            emojiLabel.isHidden = true
            emoji.customEmojiUrl?.toUIImage { image in
                DispatchQueue.main.async {
                    self.emojiImageView.image = image
                }
            }
        }
    }
    
    // MARK: Others
    
    private func adjustFontSize() {
        guard let emoji = emoji, emoji.isDefault, let defaultEmoji = emoji.defaultEmoji else { return }
        
        var labelWidth: CGFloat = 0
        var font: UIFont = emojiLabel.font ?? UIFont.systemFont(ofSize: 15.0)
        
        while frame.width - labelWidth >= 2 { // 最適なwidthとなるフォントサイズを探索する
            font = font.withSize(font.pointSize + 1)
            labelWidth = getLabelWidth(text: defaultEmoji, font: font)
        }
        
        emojiLabel.font = font
    }
}

extension EmojiView {
    @objc(EmojiModel) public class EmojiModel: NSObject, NSCoding {
        public let rawEmoji: String
        public let isDefault: Bool
        public let defaultEmoji: String?
        public let customEmojiUrl: String?
        
        init(rawEmoji: String, isDefault: Bool, defaultEmoji: String?, customEmojiUrl: String?) {
            self.rawEmoji = rawEmoji
            self.isDefault = isDefault
            self.defaultEmoji = defaultEmoji
            self.customEmojiUrl = customEmojiUrl
        }
        
        // MARK: UserDefaults Init
        
        public required init?(coder aDecoder: NSCoder) {
            rawEmoji = (aDecoder.decodeObject(forKey: "rawEmoji") ?? true) as? String ?? ""
            isDefault = (aDecoder.decodeObject(forKey: "isDefault") ?? true) as? Bool ?? true
            defaultEmoji = aDecoder.decodeObject(forKey: "defaultEmoji") as? String
            customEmojiUrl = aDecoder.decodeObject(forKey: "customEmojiUrl") as? String
        }
        
        public func encode(with aCoder: NSCoder) {
            aCoder.encode(rawEmoji, forKey: "rawEmoji")
            aCoder.encode(isDefault, forKey: "isDefault")
            aCoder.encode(defaultEmoji, forKey: "defaultEmoji")
            aCoder.encode(customEmojiUrl, forKey: "customEmojiUrl")
        }
        
        // MARK: GET/SET
        
        public static func getModelArray() -> [EmojiModel]? {
            guard let array = UserDefaults.standard.data(forKey: "[EmojiModel]") else { return nil }
            return NSKeyedUnarchiver.unarchiveObject(with: array) as? [EmojiModel] // nil許容なのでOK
        }
        
        public static func saveModelArray(with target: [EmojiModel]) {
            let targetRawData = NSKeyedArchiver.archivedData(withRootObject: target)
            UserDefaults.standard.set(targetRawData, forKey: "[EmojiModel]")
            UserDefaults.standard.synchronize()
        }
        
        public static func checkSavedArray() -> Bool { // UserDefaultsに保存されてるかcheck
            return UserDefaults.standard.object(forKey: "[EmojiModel]") != nil
        }
    }
}
