//
//  EmojiView.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/18.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Gifu
import SVGKit
import UIKit

public class EmojiView: UIView {
    @IBOutlet weak var emojiLabel: UILabel!
    @IBOutlet weak var emojiImageView: GIFImageView!
    @IBOutlet var view: UIView!
    
    public var isFake: Bool = false {
        didSet {
            guard isFake else { return }
            emojiImageView.backgroundColor = .clear
            emojiLabel.backgroundColor = .clear
        }
    }
    
    public var emoji: EmojiView.EmojiModel? {
        didSet {
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
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        setEmoji()
        adjustFontSize()
    }
    
    public func initialize() {
        emojiLabel.text = nil
        emojiImageView.image = nil
        emojiImageView.prepareForReuse() // GIFImageView → prepareForReuseしないとセルの再利用時、再利用前の画像が残ってしまう
        
        emojiLabel.isHidden = false
        emojiImageView.isHidden = false
        
        emojiImageView.backgroundColor = isFake ? .clear : .lightGray
        emojiLabel.backgroundColor = isFake ? .clear : .lightGray
    }
    
    // MARK: Emojis
    
    private func setEmoji() {
        guard let emoji = emoji else { return }
        
        initialize()
        emojiLabel.isHidden = !emoji.isDefault
        emojiImageView.isHidden = emoji.isDefault
        
        if emoji.isDefault {
            emojiLabel.text = emoji.defaultEmoji
            emojiLabel.backgroundColor = .clear
        } else {
            guard let customEmojiUrl = emoji.customEmojiUrl else { return }
            emojiImageView.setImage(url: customEmojiUrl, cachedToStorage: true) // イメージをset
        }
    }
    
    // MARK: Others
    
    // 最適なwidthとなるフォントサイズを探索する
    private func adjustFontSize() {
        guard let emoji = emoji, emoji.isDefault, let defaultEmoji = emoji.defaultEmoji else { return }
        
        var labelWidth: CGFloat = 0
        var font: UIFont = emojiLabel.font ?? UIFont.systemFont(ofSize: 15.0)
        
        var previousLabelWidth: CGFloat = 0
        while font.pointSize < 25, frame.width - labelWidth >= 2 { // フォントサイズは高々25程度だろう
            font = font.withSize(font.pointSize + 1)
            labelWidth = getLabelWidth(text: defaultEmoji, font: font)
            
            if previousLabelWidth > 0, previousLabelWidth == labelWidth { break } // widthが更新されなくなったらbreak
            previousLabelWidth = labelWidth
        }
        
        emojiLabel.font = font
    }
}

extension EmojiView {
    @objc(EmojiModel) public class EmojiModel: NSObject, NSCoding {
        // MARK: Emoji Info
        
        public let rawEmoji: String
        public let isDefault: Bool
        public let defaultEmoji: String?
        public let customEmojiUrl: String?
        
        public var isFake: Bool = false
        
        init(rawEmoji: String, isDefault: Bool, defaultEmoji: String?, customEmojiUrl: String?, isFake: Bool = false) {
            self.rawEmoji = rawEmoji
            self.isDefault = isDefault
            self.defaultEmoji = defaultEmoji
            self.customEmojiUrl = customEmojiUrl
            self.isFake = isFake
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
        
        public static var hasUserDefaultsEmojis: Bool { // UserDefaultsに保存されてるかcheck
            return UserDefaults.standard.object(forKey: "[EmojiModel]") != nil
        }
    }
}

// CollectionViewはセクションのヘッダを持たないので、自前で実装してあげる
// したがって、modelの方にヘッダー情報をねじ込む
class EmojiViewHeader: EmojiView.EmojiModel {
    // MARK: Header
    
    public var title: String
    
    init(title: String) {
        self.title = title
        super.init(rawEmoji: "", isDefault: true, defaultEmoji: nil, customEmojiUrl: nil)
    }
    
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
