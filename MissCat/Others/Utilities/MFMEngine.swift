//
//  MFMEngine.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/12/11.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit
import MisskeyKit
import YanagiText

// ** MFM実装のためのクラス **
// NSAttributedStringをplane sentencesとasync itemsにわけて、同期処理/非同期処理を両方行う

public class MFMEngine {
    
    private let original: String
    private let mfmTargets: [String]
    
    public var textColor: UIColor = .black
    
    init(_ original: String) {
        self.mfmTargets = original.regexMatches(pattern: "(:[^(\\s|:)]+:)").map{ return $0[0] }
        self.original = original
    }
    
    
    
    public func transform(yanagi: YanagiText, externalEmojis: [EmojiModel?]?)-> NSAttributedString? {
        
        var rest = original
        let shaped = NSMutableAttributedString()
        
        mfmTargets.forEach { target in
            guard let converted = EmojiHandler.handler.convertEmoji(raw: target, external: externalEmojis),
                let range = rest.range(of: target) else { return }
            
            //plane
            let plane = String(rest[rest.startIndex ..< range.lowerBound])
            shaped.append(self.generatePlaneString(string: plane, font: yanagi.font))
            
            
            
            switch converted.type {
            case "default":
                shaped.append(NSAttributedString(string: converted.emoji))
                
            case "custom":
                
                let targetView = self.generateAsyncImageView(converted.emoji)
                if let targetViewString = yanagi.getViewString(with: targetView, size: targetView.frame.size) {
                    shaped.append(targetViewString)
                }
                
            default:
                return
            }
            
            
            rest = String(rest[range.upperBound...])
        }
        
        //末端
        shaped.append(self.generatePlaneString(string: rest, font: yanagi.font))
        return shaped
    }
    
    private func generatePlaneString(string: String, font: UIFont?)->NSAttributedString {
        
        let fontName = font?.familyName ?? "Helvetica"
        let fontSize = font?.pointSize ?? 15.0
        
        var preTransed = string.hyperLink() //MUST BE DONE BEFORE ANYTHING !
        preTransed = preTransed.hyperUser()
        preTransed = preTransed.hyperHashtag()
        preTransed = preTransed.dehyperMagic()
        
        return preTransed.toAttributedString(family: fontName, size: fontSize) ?? .init()
    }
    
    
    private func generateAsyncImageView(_ imageUrl: String)-> UIImageView {
        let imageSize = 30
        
        let imageView = UIImageView()
        
        imageView.backgroundColor = .lightGray
        imageUrl.toUIImage{ image in
            DispatchQueue.main.async {
                imageView.backgroundColor = .clear
                imageView.image = image
            }
        }
        
        
        imageView.frame = CGRect(x: 0, y: 0, width: imageSize, height: imageSize)
        imageView.sizeThatFits(.init(width: imageSize, height: imageSize))
        
        return imageView
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
    
    func shapeForMFM(yanagi: YanagiText, externalEmojis: [EmojiModel?]? = nil)-> NSAttributedString? {
        let mfm = MFMEngine(self)
        return mfm.transform(yanagi: yanagi, externalEmojis: externalEmojis)
    }
}
