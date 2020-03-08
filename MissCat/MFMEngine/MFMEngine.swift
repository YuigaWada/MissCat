//
//  MFMEngine.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/12/11.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Gifu
import MisskeyKit
import SVGKit
import UIKit

// ** MFM実装のためのクラス **

public class MFMEngine {
    private var lineHeight: CGFloat = 30
    
    private let original: String
    private let emojiTargets: [String]
    
    public var textColor: UIColor = .black
    
    // MARK: Static
    
    /// リンク化・md→htmlの変換等、カスタム絵文字以外の処理を行う
    /// - Parameter string: 加工対象のstring
    public static func preTransform(string: String) -> String {
        var preTransed = string.hyperLink() // MUST BE DONE BEFORE ANYTHING !
        preTransed = preTransed.hyperUser()
        preTransed = preTransed.hyperHashtag()
        preTransed = preTransed.markdown()
        preTransed = preTransed.dehyperMagic()
        
        return preTransed
    }
    
    // MARK: Init
    
    init(with original: String, lineHeight: CGFloat? = nil) {
        emojiTargets = original.regexMatches(pattern: "(:[^(\\s|:)]+:)").map { $0[0] } // カスタム絵文字の候補を先にリストアップしておく
        self.original = original
        
        guard let lineHeight = lineHeight else { return }
        self.lineHeight = lineHeight
    }
    
    // MARK: Publics
    
    /// カスタム絵文字を検知し、対象の画像データに変換してYanagiTextに貼り付ける
    /// (Must Be Used From Main Thread !)
    /// - Parameters:
    ///   - yanagi: どのTextViewか(YanagiText)
    ///   - externalEmojis: 他インスタンスの絵文字配列
    public func transform(yanagi: YanagiText, externalEmojis: [EmojiModel?]?) -> NSAttributedString? {
        var rest = original
        let shaped = NSMutableAttributedString()
        
        // カスタム絵文字の候補をそれぞれ確認していく
        emojiTargets.forEach { target in
            guard let converted = EmojiHandler.handler.convertEmoji(raw: target, external: externalEmojis),
                let range = rest.range(of: target) else { return }
            
            // カスタム絵文字を支点に文章を分割していく
            let plane = String(rest[rest.startIndex ..< range.lowerBound])
            shaped.append(MFMEngine.generatePlaneString(string: plane, font: yanagi.font))
            
            // カスタム絵文字を適切な形に変換していく
            switch converted.type {
            case "default":
                shaped.append(NSAttributedString(string: converted.emoji))
                
            case "custom":
                let targetView = MFMEngine.generateAsyncImageView(imageUrl: converted.emoji, lineHeight: lineHeight)
                if let targetViewString = yanagi.getViewString(with: targetView, size: targetView.frame.size) {
                    shaped.append(targetViewString)
                }
                
            default:
                return
            }
            
            rest = String(rest[range.upperBound...])
        }
        
        // 末端
        shaped.append(MFMEngine.generatePlaneString(string: rest, font: yanagi.font))
        return shaped
    }
    
    // MARK: Statics
    
    /// Stringを適切なフォントを指定してNSAttributedStringに変換する
    /// - Parameters:
    ///   - string: 対象のstring
    ///   - font: フォント
    public static func generatePlaneString(string: String, font: UIFont?) -> NSAttributedString {
        let fontName = font?.familyName ?? "Helvetica"
        let fontSize = font?.pointSize ?? 15.0
        
        return string.toAttributedString(family: fontName, size: fontSize) ?? .init()
    }
    
    /// カスタム絵文字のURLから画像データを取得し、非同期でsetされるようなUIImageViewを返す
    /// - Parameter imageUrl: 画像データのurl (アニメGIF / SVGも可)
    public static func generateAsyncImageView(imageUrl: String, lineHeight: CGFloat = 30) -> UIImageView {
        let imageSize = lineHeight
        let imageView = GIFImageView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        
        imageView.backgroundColor = .lightGray
        imageView.frame = CGRect(x: 0, y: 0, width: imageSize, height: imageSize)
        imageView.sizeThatFits(.init(width: imageSize, height: imageSize))
        
        imageView.setImage(url: imageUrl)
        
        return imageView
    }
}

// MARK: String Extension

// 装飾関係
extension String {
    // Emoji形式":hogehoge:"をデフォルト絵文字 / カスタム絵文字のurl/imgに変更
    func emojiEncoder(externalEmojis: [EmojiModel?]?) -> String {
        return EmojiHandler.handler.emojiEncoder(note: self, externalEmojis: externalEmojis)
    }
    
    // linkをリンク化
    // この時、urlに@が入ると後々hyperUserと干渉するので、
    // @ → [at-mark.misscat.header] / # → [hash-tag.misscat.header] に変換しておく
    func hyperLink() -> String {
        // markdown link
        var result = replacingOccurrences(of: "\\[([^\\]]+)\\]\\(([^\\)]+)\\)",
                                          with: "<a style=\"color: [hash-tag.misscat.header]2F7CF6;\" href=\"$2\">$1</a>",
                                          options: .regularExpression)
        
        // normal Link
        let normalLink = "(https?://[\\w/:%#\\$&\\?\\(~\\.=\\+\\-@\"]+)"
        let targets = result.regexMatches(pattern: normalLink).map { $0[0] }.filter {
            $0.suffix(1) != "\""
        }
        
        // 先ににaタグに変換しておくと都合が良い
        
        targets.forEach { target in
            var to = target.replacingOccurrences(of: "@", with: "[at-mark.misscat.header]")
            to = to.replacingOccurrences(of: "#", with: "[hash-tag.misscat.header]")
            
            result = result.replacingOccurrences(of: target,
                                                 with: "<a style=\"color: [hash-tag.misscat.header]2F7CF6;\" href=\"\(to)\">\(to)</a>")
        }
        
        return result
    }
    
    func markdown() -> String {
        let bold = replacingOccurrences(of: "\\*\\*([^\\*]+)\\*\\*",
                                        with: "<b>$1</b>",
                                        options: .regularExpression)
        
        let strikeThrough = bold.replacingOccurrences(of: "~~([^\\~]+)~~",
                                                      with: "<s>$1</s>",
                                                      options: .regularExpression)
        
        return strikeThrough.disablingTags()
    }
    
    func disablingTags() -> String {
        var result = self
        let targetTags = ["motion", "flip", "spin", "jump", "small"]
        let otherTargets: [String: String] = ["***": "***", "(((": ")))"]
        
        targetTags.forEach { tag in
            let open = "<\(tag)>"
            let close = "</\(tag)>"
            
            result = result.replacingOccurrences(of: open, with: "").replacingOccurrences(of: close, with: "")
        }
        
        otherTargets.forEach { open, close in
            result = result.replacingOccurrences(of: open, with: "").replacingOccurrences(of: close, with: "")
        }
        
        return result
    }
    
    // usernameをリンク化
    func hyperUser() -> String {
        return replacingOccurrences(of: "(@([a-zA-Z0-9]|\\.|_|@)+)",
                                    with: "<a style=\"color: [hash-tag.misscat.header]2F7CF6;\" href=\"http://tapEvents.misscat/$0\">$0</a>",
                                    options: .regularExpression)
    }
    
    func hyperHashtag() -> String {
        return replacingOccurrences(of: "(#[^(\\s|,)]+)",
                                    with: "<a style=\"color: [hash-tag.misscat.header]2F7CF6;\" href=\"http://hashtags.misscat/$0\">$0</a>",
                                    options: .regularExpression)
    }
    
    func dehyperMagic() -> String {
        return replacingOccurrences(of: "[at-mark.misscat.header]", with: "@")
            .replacingOccurrences(of: "[hash-tag.misscat.header]", with: "#")
    }
    
    func mfmPreTransform() -> String {
        return MFMEngine.preTransform(string: self)
    }
    
    // Must Be Used From Main Thread !
    func mfmTransform(yanagi: YanagiText, externalEmojis: [EmojiModel?]? = nil, lineHeight: CGFloat? = nil) -> NSAttributedString? {
        let mfm = MFMEngine(with: self, lineHeight: lineHeight)
        return mfm.transform(yanagi: yanagi, externalEmojis: externalEmojis)
    }
}

extension NoteModel {
    func mfmPreTransform() -> NoteModel {
        text = MFMEngine.preTransform(string: text ?? "")
        return self
    }
}
