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

class EmojiView: UIView {
    @IBOutlet weak var emojiLabel: UILabel!
    
    @IBOutlet weak var emojiImageView: MFMImageView!
    @IBOutlet var view: UIView!
    
    var isFake: Bool = false {
        didSet {
            guard isFake else { return }
            emojiImageView.backgroundColor = .clear
            emojiLabel.backgroundColor = .clear
        }
    }
    
    var emoji: EmojiView.EmojiModel? {
        didSet {
            self.setEmoji()
        }
    }
    
    // MARK: Life Cycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        loadNib()
        backgroundColor = .clear
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
        loadNib()
        backgroundColor = .clear
    }
    
    func loadNib() {
        if let view = UINib(nibName: "EmojiView", bundle: Bundle(for: type(of: self))).instantiate(withOwner: self, options: nil)[0] as? UIView {
            view.frame = bounds
            view.backgroundColor = .clear
            addSubview(view)
            adjustFontSize()
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        setEmoji()
    }
    
    func initialize() {
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
    
    // 最適なフォントサイズに変更する
    private func adjustFontSize() {
        let font: UIFont = emojiLabel.font ?? UIFont.systemFont(ofSize: 50.0)
        emojiLabel.font = font.withSize(50) // 多分shrinkが効いていい感じのサイズになる
    }
}

extension EmojiView {
    enum EmojiType: String {
        case favs
        case history
    }
    
    @objc(EmojiModel) class EmojiModel: NSObject, NSCoding {
        let rawEmoji: String
        let isDefault: Bool
        let defaultEmoji: String?
        let customEmojiUrl: String?
        
        var isFake: Bool = false
        
        init(rawEmoji: String, isDefault: Bool, defaultEmoji: String?, customEmojiUrl: String?, isFake: Bool = false) {
            self.rawEmoji = rawEmoji
            self.isDefault = isDefault
            self.defaultEmoji = defaultEmoji
            self.customEmojiUrl = customEmojiUrl
            self.isFake = isFake
        }
        
        // MARK: UserDefaults Init
        
        required init?(coder aDecoder: NSCoder) {
            rawEmoji = aDecoder.decodeObject(forKey: "rawEmoji") as? String ?? ""
            isDefault = aDecoder.decodeBool(forKey: "isDefault")
            defaultEmoji = aDecoder.decodeObject(forKey: "defaultEmoji") as? String
            customEmojiUrl = aDecoder.decodeObject(forKey: "customEmojiUrl") as? String
        }
        
        func encode(with aCoder: NSCoder) {
            aCoder.encode(rawEmoji, forKey: "rawEmoji")
            aCoder.encode(isDefault, forKey: "isDefault")
            aCoder.encode(defaultEmoji, forKey: "defaultEmoji")
            aCoder.encode(customEmojiUrl, forKey: "customEmojiUrl")
        }
        
        // MARK: GET/SET
        
        static func getEmojis(type: EmojiType) -> [EmojiModel]? {
            guard let array = UserDefaults.standard.data(forKey: type.rawValue) else { return nil }
            return NSKeyedUnarchiver.unarchiveObject(with: array) as? [EmojiModel] // nil許容なのでOK
        }
        
        static func saveEmojis(with target: [EmojiModel], type: EmojiType) {
            let targetRawData = NSKeyedArchiver.archivedData(withRootObject: target)
            UserDefaults.standard.set(targetRawData, forKey: type.rawValue)
            UserDefaults.standard.synchronize()
        }
        
        static var hasFavEmojis: Bool { // UserDefaultsに保存されてるかcheck
            return UserDefaults.standard.object(forKey: EmojiType.favs.rawValue) != nil
        }
        
        static var hasHistory: Bool { // UserDefaultsに保存されてるかcheck
            return UserDefaults.standard.object(forKey: EmojiType.history.rawValue) != nil
        }
    }
}

// CollectionViewはセクションのヘッダを持たないので、自前で実装してあげる
// したがって、modelの方にヘッダー情報をねじ込む
class EmojiViewHeader: EmojiView.EmojiModel {
    // MARK: Header
    
    var title: String
    
    init(title: String) {
        self.title = title
        super.init(rawEmoji: "", isDefault: true, defaultEmoji: nil, customEmojiUrl: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
