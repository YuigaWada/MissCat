//
//  EmojiHandler.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/13.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit

typealias CategorizedEmojis = [String: [EmojiView.EmojiModel]]

extension EmojiHandler {
    enum EmojiType {
        case `default` // デフォルト絵文字
        case custom // カスタム絵文字
        case nonColon // v12で廃止 (ノンコロン絵文字: confused→😥みたいにコロンで挟まれない絵文字)
    }
    
    struct RawEmoji {
        let type: EmojiType
        let emoji: String
    }
    
    // ノンコロン絵文字: 上記参照
    struct NonColonEmoji {
        let name: String
        let emoji: String
    }
}

class EmojiHandler {
    // setされた瞬間カテゴリー分けを行うが、カスタム絵文字を先にcategorizedEmojisへ格納する
    var defaultEmojis: [DefaultEmojiModel]? {
        didSet {
            guard let defaultEmojis = defaultEmojis else { return }
            categorizeDefaultEmojis(defaultEmojis)
        }
    }
    
    var customEmojis: [EmojiModel]? {
        didSet {
            guard let customEmojis = customEmojis else { return }
            categorizeCustomEmojis(customEmojis)
        }
    }
    
    private lazy var nonColonEmojis: [NonColonEmoji] = getNonColonEmojis()
    
    // 絵文字のカテゴリーによって分類分けする(Dictionaryは順序を保証しないので、デフォルト・カスタムで分割する)
    var categorizedDefaultEmojis: CategorizedEmojis = .init()
    var categorizedCustomEmojis: CategorizedEmojis = .init()
    
    let owner: SecureUser
    
    // MARK: Static
    
    private static var handlers: [EmojiHandler] = []
    static func setHandler(owner: SecureUser) {
        if let _ = getHandler(owner: owner) { return } // すでに同じインスタンスの絵文字が登録されていたらsetしない
        guard let misskey = MisskeyKit(from: owner) else { return }
        let newHandler = EmojiHandler(from: misskey, owner: owner)
        handlers.append(newHandler)
    }
    
    static func getHandler(owner: SecureUser) -> EmojiHandler? {
        let option = handlers.filter { $0.owner.instance == owner.instance } // インスタンスごとに絵文字を管理
        return option.count > 0 ? option[0] : nil
    }
    
    // MARK: Public
    
    init(from misskey: MisskeyKit, owner: SecureUser) { // 先に絵文字情報をダウンロードしておく
        self.owner = owner
        misskey.emojis.getDefault { self.defaultEmojis = $0 }
        misskey.emojis.getCustom { self.customEmojis = $0 }
    }
    
    /// 自インスタンス・他インスタンスに拘らず、絵文字をデフォルト絵文字かカスタム絵文字のurlに変換する
    /// - Parameters:
    ///   - raw: :hoge_hoge:形式の絵文字
    ///   - external: 他インスタンス由来の絵文字配列
    func convertEmoji(raw: String, external: [EmojiModel?]? = nil) -> RawEmoji? {
        // 自インスタンス由来のEmoji
        let encoded = encodeEmoji(raw: raw)
        
        if let defaultEmoji = encoded as? DefaultEmojiModel, let emoji = defaultEmoji.char {
            return RawEmoji(type: .default, emoji: emoji)
        } else if let customEmoji = encoded as? EmojiModel, let emojiUrl = customEmoji.url {
            return RawEmoji(type: .custom, emoji: emojiUrl)
        } else if let nonColonEmoji = encoded as? NonColonEmoji {
            let emoji = nonColonEmoji.emoji
            return RawEmoji(type: .nonColon, emoji: emoji)
        }
        
        // 他インスタンス由来のEmoji
        guard let external = external else { return nil }
        let externalEmojis = external.filter { $0 != nil }
        
        let options = externalEmojis.filter { self.checkName($0!.name, input: raw) } // 候補を探る
        guard options.count > 0, let emojiUrl = options[0]?.url else { return nil }
        
        return RawEmoji(type: .custom, emoji: emojiUrl)
    }
    
    /// 自インスタンス由来の絵文字をデフォルト絵文字かカスタム絵文字のurlに変換する
    /// - Parameter raw: :hoge_hoge:形式の絵文字
    func encodeEmoji(raw: String) -> Any? {
        guard let defaultEmojis = defaultEmojis, let customEmojis = customEmojis else { return nil }
        
        // name: "wara"  char: "(^o^)"
        
        if nonColonEmojis.filter({ $0.name == raw }).count > 0 {
            return nonColonEmojis.filter { $0.name == raw }[0]
        }
        
        let defaultOption = defaultEmojis.filter { self.checkName($0.name, input: raw) }
        let customOption = customEmojis.filter { self.checkName($0.name, input: raw) }
        
        if defaultOption.count > 0 {
            return defaultOption[0]
        } else if customOption.count > 0 {
            return customOption[0]
        }
        
        return nil
    }
    
    private func checkName(_ name: String?, input raw: String) -> Bool {
        guard let name = name else { return false }
        return raw == ":" + name + ":" || raw == name || raw.replacingOccurrences(of: ":", with: "") == name
    }
    
    func convert2EmojiModel(raw: String, external externalEmojis: [EmojiModel] = []) -> EmojiView.EmojiModel {
        guard let convertedEmojiData = convertEmoji(raw: raw, external: externalEmojis)
        else {
            return .init(rawEmoji: raw,
                         isDefault: true,
                         defaultEmoji: raw,
                         customEmojiUrl: nil)
        }
        
        let isDefault = convertedEmojiData.type == .default
        let isNonColonEmoji = convertedEmojiData.type == .nonColon
        if isNonColonEmoji {
            return EmojiView.EmojiModel(rawEmoji: raw,
                                        isDefault: true,
                                        defaultEmoji: convertedEmojiData.emoji,
                                        customEmojiUrl: nil)
        } else {
            return EmojiView.EmojiModel(rawEmoji: raw,
                                        isDefault: isDefault,
                                        defaultEmoji: isDefault ? raw : nil,
                                        customEmojiUrl: isDefault ? nil : convertedEmojiData.emoji)
        }
    }
    
    /// デフォルト絵文字をカテゴリーにとって分類する
    /// - Parameter emojis: デフォルト絵文字のmodel
    private func categorizeDefaultEmojis(_ emojis: [DefaultEmojiModel]) {
        emojis.forEach { emoji in
            guard let raw = emoji.name, let char = emoji.char else { return }
            
            let emojiModel = EmojiView.EmojiModel(rawEmoji: raw, // 絵文字モデル
                                                  isDefault: true,
                                                  defaultEmoji: char,
                                                  customEmojiUrl: nil)
            
            var category = emoji.category?.rawValue ?? ""
            category = category != "" ? category : "Others"
            if let _ = categorizedDefaultEmojis[category] { // key: categoryであるArrayが格納されているならば...
                categorizedDefaultEmojis[category]?.append(emojiModel)
            } else {
                categorizedDefaultEmojis[category] = [emojiModel]
            }
        }
    }
    
    /// カスタム絵文字をカテゴリーによって分類する
    /// - Parameter emojis: カスタム絵文字のmodel
    private func categorizeCustomEmojis(_ emojis: [EmojiModel]) {
        emojis.forEach { emoji in
            guard let raw = emoji.name, let url = emoji.url else { return }
            
            let emojiModel = EmojiView.EmojiModel(rawEmoji: raw, // 絵文字モデル
                                                  isDefault: false,
                                                  defaultEmoji: nil,
                                                  customEmojiUrl: url)
            
            var category = emoji.category ?? ""
            category = category != "" ? category : "Others"
            if let _ = categorizedCustomEmojis[category] { // key: categoryであるArrayが格納されているならば...
                categorizedCustomEmojis[category]?.append(emojiModel)
            } else {
                categorizedCustomEmojis[category] = [emojiModel]
            }
        }
    }
    
    private func getNonColonEmojis() -> [NonColonEmoji] {
        let emojis = ["like": "👍",
                      "love": "❤️",
                      "laugh": "😆",
                      "hmm": "🤔",
                      "surprise": "😮",
                      "congrats": "🎉",
                      "angry": "💢",
                      "confused": "😥",
                      "rip": "😇",
                      "pudding": "🍮",
                      "star": "⭐"]
        
        return emojis.map { NonColonEmoji(name: $0, emoji: $1) }
    }
    
    // Emoji形式":hogehoge:"をデフォルト絵文字 / カスタム絵文字のurl/imgに変更
    func emojiEncoder(note: String, externalEmojis: [EmojiModel?]?) -> String {
        var newNote = note
        let targets = note.regexMatches(pattern: "(:[^(\\s|:)]+:)")
        
        guard targets.count > 0 else { return note }
        targets.forEach { target in
            guard target.count > 0 else { return }
            let target = target[0]
            
            guard let converted = convertEmoji(raw: target, external: externalEmojis)
            else { return }
            
            switch converted.type {
            case .default:
                newNote = newNote.replacingOccurrences(of: target, with: converted.emoji)
                
            case .custom:
                newNote = newNote.replacingOccurrences(of: target, with: "<img width=\"30\" height=\"30\"  src=\"\(converted.emoji)\">") // TODO: ここのrenderingが遅い / ここでnewNoteを分割
                
            default:
                break
            }
        }
        
        return newNote
    }
}
