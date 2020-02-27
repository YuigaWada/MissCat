//
//  EmojiHandler.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/13.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit

public class EmojiHandler {
    // setされた瞬間カテゴリー分けを行うが、カスタム絵文字を先にcategorizedEmojisへ格納する
    public var defaultEmojis: [DefaultEmojiModel]? {
        didSet {
            guard let defaultEmojis = defaultEmojis else { return }
            categorizeDefaultEmojis(defaultEmojis)
        }
    }
    
    public var customEmojis: [EmojiModel]? {
        didSet {
            guard let customEmojis = customEmojis else { return }
            categorizeCustomEmojis(customEmojis)
        }
    }
    
    // 絵文字のカテゴリーによって分類分けする(Dictionaryは順序を保証しないので、デフォルト・カスタムで分割する)
    public var categorizedDefaultEmojis: [String: [EmojiView.EmojiModel]] = .init()
    public var categorizedCustomEmojis: [String: [EmojiView.EmojiModel]] = .init()
    
    public static let handler = EmojiHandler() // Singleton
    
    init() { // 先に絵文字情報をダウンロードしておく
        MisskeyKit.Emojis.getDefault { self.defaultEmojis = $0 }
        MisskeyKit.Emojis.getCustom { self.customEmojis = $0 }
    }
    
    /// 自インスタンス・他インスタンスに拘らず、絵文字をデフォルト絵文字かカスタム絵文字のurlに変換する
    /// - Parameters:
    ///   - raw: :hoge_hoge:形式の絵文字
    ///   - external: 他インスタンス由来の絵文字配列
    public func convertEmoji(raw: String, external: [EmojiModel?]? = nil) -> (type: String, emoji: String)? {
        // 自インスタンス由来のEmoji
        let encoded = encodeEmoji(raw: raw)
        
        if let defaultEmoji = encoded as? DefaultEmojiModel, let emoji = defaultEmoji.char {
            return ("default", emoji)
        } else if let customEmoji = encoded as? EmojiModel, let emojiUrl = customEmoji.url {
            return ("custom", emojiUrl)
        }
        
        // 他インスタンス由来のEmoji
        guard let external = external else { return nil }
        let externalEmojis = external.filter { $0 != nil }
        
        let options = externalEmojis.filter { self.checkName($0!.name, input: raw) } // 候補を探る
        guard options.count > 0, let emojiUrl = options[0]?.url else { return nil }
        
        return ("custom", emojiUrl)
    }
    
    /// 自インスタンス由来の絵文字をデフォルト絵文字かカスタム絵文字のurlに変換する
    /// - Parameter raw: :hoge_hoge:形式の絵文字
    public func encodeEmoji(raw: String) -> Any? {
        guard let defaultEmojis = defaultEmojis, let customEmojis = customEmojis else { return nil }
        
        // name: "wara"  char: "(^o^)"
        
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
    
    static func convert2EmojiModel(raw: String) -> EmojiView.EmojiModel {
        guard let convertedEmojiData = EmojiHandler.handler.convertEmoji(raw: raw)
        else {
            return .init(rawEmoji: raw,
                         isDefault: true,
                         defaultEmoji: raw,
                         customEmojiUrl: nil)
        }
        
        let isDefault = convertedEmojiData.type == "default"
        
        return EmojiView.EmojiModel(rawEmoji: raw,
                                    isDefault: isDefault,
                                    defaultEmoji: isDefault ? raw : nil,
                                    customEmojiUrl: isDefault ? nil : convertedEmojiData.emoji)
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
    
    // Emoji形式":hogehoge:"をデフォルト絵文字 / カスタム絵文字のurl/imgに変更
    // TODO: このメソッドはレガシーで今は使わないはず？？
    public func emojiEncoder(note: String, externalEmojis: [EmojiModel?]?) -> String {
        var newNote = note
        let targets = note.regexMatches(pattern: "(:[^(\\s|:)]+:)")
        
        guard targets.count > 0 else { return note }
        targets.forEach { target in
            guard target.count > 0 else { return }
            let target = target[0]
            
            guard let converted = EmojiHandler.handler.convertEmoji(raw: target, external: externalEmojis)
            else { return }
            
            switch converted.type {
            case "default":
                newNote = newNote.replacingOccurrences(of: target, with: converted.emoji)
                
            case "custom":
                newNote = newNote.replacingOccurrences(of: target, with: "<img width=\"30\" height=\"30\"  src=\"\(converted.emoji)\">") // TODO: ここのrenderingが遅い / ここでnewNoteを分割
                
            default:
                break
            }
        }
        
        return newNote
    }
}
