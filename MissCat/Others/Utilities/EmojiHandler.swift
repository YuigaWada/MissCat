//
//  EmojiHandler.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/13.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit

public class EmojiHandler {
    
    private var defaultEmojis: [DefaultEmojiModel]?
    private var customEmojis: [EmojiModel]?
    
    public static let handler = EmojiHandler()
    
    
    init() {
        MisskeyKit.Emojis.getDefault{ self.defaultEmojis = $0 }
        MisskeyKit.Emojis.getCustom{ self.customEmojis = $0 }
    }
    
    
    //Emoji形式":hogehoge:"をデフォルト絵文字 / カスタム絵文字のurl/imgに変更
    public func emojiEncoder(note: String, externalEmojis: [EmojiModel?]?)-> String {
        
        var newNote = note
        let targets = note.regexMatches(pattern: "(:[^\\s]+:)")
        
        guard targets.count > 0 else { return note }
        targets.forEach{ target in
            guard target.count > 0 else { return }
            let target = target[0]
            
            guard let converted = EmojiHandler.handler.convertEmoji(raw: target, external: externalEmojis)
                else { return }
            
            switch converted.type {
            case "default":
                newNote = newNote.replacingOccurrences(of: target, with: converted.emoji)
                
            case "custom":
                newNote = newNote.replacingOccurrences(of: target, with:  "<img width=\"30\" height=\"30\"  src=\"\(converted.emoji)\">") //TODO: ここのrenderingが遅い / ここでnewNoteを分割
                
            default:
                break
            }
        }
        
        return newNote
    }
    
    
    
    public func convertEmoji(raw: String, external: [EmojiModel?]? = nil)-> (type: String, emoji: String)? {
        
        //自インスタンス由来のEmoji
        let encoded = self.encodeEmoji(raw: raw)
        
        if let defaultEmoji = encoded as? DefaultEmojiModel, let emoji = defaultEmoji.char {
            return ("default", emoji)
        }
        else if let customEmoji = encoded as? EmojiModel, let emojiUrl = customEmoji.url {
            return ("custom", emojiUrl)
        }
    
        //他インスタンス由来のEmoji
        guard let external = external else { return nil }
        let externalEmojis = external.filter { $0 != nil }
        
        let options = externalEmojis.filter { self.checkName($0!.name, input: raw) } //候補を探る
        guard options.count > 0, let emojiUrl = options[0]?.url else { return nil }
        
        return ("custom", emojiUrl)
    }
    
    
    // String → Emoji
    public func encodeEmoji(raw: String)-> Any? {
        
        guard let defaultEmojis = defaultEmojis, let customEmojis = customEmojis else { return nil }
        
        //name: "wara"  char: "(^o^)"
        
        let defaultOption = defaultEmojis.filter{ self.checkName($0.name, input: raw) }
        let customOption = customEmojis.filter{ self.checkName($0.name, input: raw) }
        
        if defaultOption.count > 0 {
            return defaultOption[0]
        }
        else if customOption.count > 0 {
            return customOption[0]
        }
        
        return nil
    }


    
    private func checkName(_ name: String?, input raw: String)-> Bool {
        guard let name = name else { return false }
        return raw == ":" + name + ":" || raw == name || raw.replacingOccurrences(of: ":", with: "") == name
    }
}
