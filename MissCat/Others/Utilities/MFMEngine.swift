//
//  MFMEngine.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/12/11.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit
import MisskeyKit

// ** MFM実装のためのクラス **
// NSAttributedStringをplane sentencesとasync itemsにわけて、同期処理/非同期処理を両方行う

public class MFMEngine {
    
    private var syncItems: [NSAttributedString] = []
    private var asyncItems: [NSAttributedString] = []
    
    public init(_ attributedString: NSAttributedString) {
        
    }
}


// 装飾関係
extension String {
    //Emoji形式":hogehoge:"をデフォルト絵文字 / カスタム絵文字のurl/imgに変更
    func emojiEncoder(externalEmojis: [EmojiModel?]?)-> String {
        return EmojiHandler.handler.emojiEncoder(note: self, externalEmojis: externalEmojis)
    }
    
    
    // linkをリンク化
    // この時、urlに@が入ると後々hyperUserと干渉するので、
    // @ → [at-mark.misscat.header] / # → [hash-tag.misscat.header] に変換しておく
    func hyperLink()-> String {
        
//        let basedPattern = "https?://[\\w/:%#\\$&\\?\\(\\)~\\.=\\+\\-@]+"
//        let pattern = "([^\\(href=\"\\)]+\(basedPattern)|^\(basedPattern))" //Markdownの[hoge](~~)を考慮して(にくるまれてるものは非適応に)
        
        let pattern = "(https?://[\\w/:%#\\$&\\?\\(\\)~\\.=\\+\\-@]+)"
        let targets = self.regexMatches(pattern: pattern)
        
        guard targets.count > 0 else { return self }
        
        //先ににaタグに変換しておくと都合が良い
        var result: String = self.replacingOccurrences(of: pattern,
                                                       with: "<a style=\"color: [hash-tag.misscat.header]2F7CF6;\" href=\"$0\">$0</a>",
                                                       options: .regularExpression)
        targets.forEach{ target in
            guard target.count > 0 else { return }
            
            let from = target[0]
            var to = from.replacingOccurrences(of: "@", with: "[at-mark.misscat.header]")
            to = to.replacingOccurrences(of: "#", with: "[hash-tag.misscat.header]")
            
            result = result.replacingOccurrences(of: from, with: to)
        }
        
        return result
    }
    
    
    // usernameをリンク化
    func hyperUser()-> String {
        return self.replacingOccurrences(of: "(@([a-zA-Z0-9]|\\.|_|@)+)",
                                         with: "<a style=\"color: [hash-tag.misscat.header]2F7CF6;\" href=\"http://tapEvents.misscat/$0\">$0</a>",
                                         options: .regularExpression)
    }
    
    
    func hyperHashtag()-> String {
        return self.replacingOccurrences(of: "(#[^\\s]+)",
                                         with: "<a style=\"color: [hash-tag.misscat.header]2F7CF6;\" href=\"http://hashtags.misscat/$0\">$0</a>",
                                         options: .regularExpression)
        
        
    }
    
    func dehyperMagic()-> String {
        return self.replacingOccurrences(of: "[at-mark.misscat.header]", with: "@")
            .replacingOccurrences(of: "[hash-tag.misscat.header]", with:"#")
    }
    
    func shapeForMFM(externalEmojis: [EmojiModel?]? = nil)-> String {
//        var shaped = (try? Down(markdownString: self).toHTML(.unsafe)) ?? self
        var shaped = self.hyperLink() //MUST BE DONE BEFORE ANYTHING !
        shaped = shaped.emojiEncoder(externalEmojis: externalEmojis)
        shaped = shaped.hyperUser()
        shaped = shaped.hyperHashtag()
        shaped = shaped.dehyperMagic()
        
        return shaped
    }
}
