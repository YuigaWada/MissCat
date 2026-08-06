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
        emojiLabel.backgroundColor = .clear
    }
    
    // MARK: Emojis
        
    private func setEmoji() {
        guard let emoji = emoji else { return }
        
        initialize()
        emojiImageView.isHidden = false
        
        var customEmojiUrl = emoji.customEmojiUrl
        if emoji.isDefault,
           let defaultEmoji = emoji.defaultEmoji
        {
            customEmojiUrl = MFMEngine.getTwemojiURL(for: defaultEmoji)
        }
        
        if let customEmojiUrl = customEmojiUrl {
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
    
    @objc(EmojiModel) class EmojiModel: NSObject, NSSecureCoding {
        static var supportsSecureCoding: Bool { true }

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
            rawEmoji = aDecoder.decodeObject(of: NSString.self, forKey: "rawEmoji") as String? ?? ""
            isDefault = aDecoder.decodeBool(forKey: "isDefault")
            defaultEmoji = aDecoder.decodeObject(of: NSString.self, forKey: "defaultEmoji") as String?
            customEmojiUrl = aDecoder.decodeObject(of: NSString.self, forKey: "customEmojiUrl") as String?
        }
        
        func encode(with aCoder: NSCoder) {
            aCoder.encode(rawEmoji, forKey: "rawEmoji")
            aCoder.encode(isDefault, forKey: "isDefault")
            aCoder.encode(defaultEmoji, forKey: "defaultEmoji")
            aCoder.encode(customEmojiUrl, forKey: "customEmojiUrl")
        }
        
        // MARK: GET/SET
        
        static func getEmojis(type: EmojiType, owner: SecureUser) -> [EmojiModel]? {
            let key = getKey(type: type, owner: owner)
            guard let array = UserDefaults.standard.data(forKey: key) else { return nil }
            guard let decoded = decodeStoredEmojis(array) else {
                // Corrupt archives must not crash every subsequent picker launch.
                UserDefaults.standard.removeObject(forKey: key)
                UserDefaults.standard.removeObject(forKey: storageVersionKey(key))
                return nil
            }
            let sanitized = sanitize(decoded, type: type)
            if UserDefaults.standard.integer(forKey: storageVersionKey(key)) < 2 || sanitized.count != decoded.count {
                saveEmojis(with: sanitized, type: type, owner: owner)
            }
            return sanitized
        }
        
        static func saveEmojis(with target: [EmojiModel], type: EmojiType, owner: SecureUser) {
            let key = getKey(type: type, owner: owner)
            let sanitized = sanitize(target, type: type)
            guard let targetRawData = try? archiveEmojis(sanitized) else { return }

            UserDefaults.standard.set(targetRawData, forKey: key)
            UserDefaults.standard.set(2, forKey: storageVersionKey(key))
        }
        
        static func checkHavingEmojis(type: EmojiType, owner: SecureUser) -> Bool {
            let key = getKey(type: type, owner: owner)
            return UserDefaults.standard.object(forKey: key) != nil
        }
        
        private static func getKey(type: EmojiType, owner: SecureUser) -> String {
            return "\(type.rawValue)-\(owner.instance)" // 絵文字情報はインスタンスごとに管理する
        }

        static func archiveEmojis(_ target: [EmojiModel]) throws -> Data {
            try NSKeyedArchiver.archivedData(withRootObject: target, requiringSecureCoding: true)
        }

        static func decodeStoredEmojis(_ data: Data) -> [EmojiModel]? {
            let allowed: [AnyClass] = [NSArray.self, EmojiModel.self, NSString.self, NSNumber.self]
            if let secure = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: allowed, from: data) as? [EmojiModel] {
                return secure
            }

            // One read of the pre-2026 non-secure archive is supported so existing
            // favorites/history can be migrated immediately to the secure v2 archive.
            return (try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data)) as? [EmojiModel]
        }

        private static func sanitize(_ target: [EmojiModel], type: EmojiType) -> [EmojiModel] {
            var seen: Set<String> = []
            let valid = target.filter { model in
                guard !model.isFake, !model.rawEmoji.isEmpty else { return false }
                if !model.isDefault {
                    guard let rawURL = model.customEmojiUrl,
                          let url = URL(string: rawURL),
                          ["http", "https"].contains(url.scheme?.lowercased() ?? "")
                    else { return false }
                }
                return seen.insert("\(model.rawEmoji)|\(model.customEmojiUrl ?? "")").inserted
            }
            return type == .history ? Array(valid.prefix(14)) : valid
        }

        private static func storageVersionKey(_ key: String) -> String {
            "\(key).secure-archive-version"
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
    
    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
