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

struct MFMString {
    let mfmEngine: MFMEngine
    var attributed: NSAttributedString?
}

class MFMEngine {
    private var lineHeight: CGFloat = 30
    
    private let original: String
    private let emojiTargets: [String]
    
    // 　この２つは順序が等しくなるよう気をつけて格納していく
    private var customEmojis: [String] = []
    private var attachments: [NSTextAttachment] = []
    
    static var usernameFont = UIFont.systemFont(ofSize: 11.0)
    
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
    func transform(owner: SecureUser?, font: UIFont, externalEmojis: [EmojiModel?]?, textHex: String?) -> NSAttributedString? {
        var rest = original
        let shaped = NSMutableAttributedString()
        
        guard let owner = owner,
            let handler = EmojiHandler.getHandler(owner: owner) else { return MFMEngine.generatePlaneString(string: rest, font: font, textHex: textHex) }
        
        // カスタム絵文字の候補をそれぞれ確認していく
        emojiTargets.forEach { target in
            guard let converted = handler.convertEmoji(raw: target, external: externalEmojis),
                let range = rest.range(of: target) else { return }
            
            // カスタム絵文字を支点に文章を分割していく
            let plane = String(rest[rest.startIndex ..< range.lowerBound])
            shaped.append(MFMEngine.generatePlaneString(string: plane, font: font, textHex: textHex))
            
            // カスタム絵文字を適切な形に変換していく
            switch converted.type {
            case .default:
                shaped.append(NSAttributedString(string: converted.emoji))
                
            case .custom:
                let (attachmentString, attachment) = YanagiText.getAttachmentString(size: CGSize(width: lineHeight, height: lineHeight))
                if let attachmentString = attachmentString {
                    shaped.append(attachmentString)
                    
                    customEmojis.append(converted.emoji)
                    attachments.append(attachment)
                }
            default:
                break
            }
            
            rest = String(rest[range.upperBound...])
        }
        
        // 末端
        shaped.append(MFMEngine.generatePlaneString(string: rest, font: font, textHex: textHex))
        return shaped
    }
    
    /// カスタム絵文字を表示するViewを生成し、YanagiTextへAddする
    /// - Parameter yanagi: YanagiText
    func renderCustomEmojis(on yanagi: YanagiText) {
        guard customEmojis.count == attachments.count else { return }
        
        for index in 0 ..< customEmojis.count {
            let customEmoji = customEmojis[index]
            let attachment = attachments[index]
            
            let targetView = MFMEngine.generateAsyncImageView(imageUrl: customEmoji, lineHeight: lineHeight)
            let yanagiAttachment = YanagiText.Attachment(view: targetView, size: targetView.frame.size)
            
            yanagi.addAttachment(ns: attachment, yanagi: yanagiAttachment)
        }
    }
    
    // MARK: Statics
    
    /// リンク化・md→htmlの変換等、カスタム絵文字以外の処理を行う
    /// - Parameter string: 加工対象のstring
    static func preTransform(string: String) -> String {
        var preTransed = hyperLink(string) // MUST BE DONE BEFORE ANYTHING !
        preTransed = hyperUser(preTransed)
        preTransed = hyperHashtag(preTransed)
        preTransed = markdown(preTransed)
        preTransed = dehyperMagic(preTransed)
        
        return preTransed
    }
    
    // MARK: Shape
    
    /// NotificationCell.Modelを整形する
    /// - Parameter cellModel: NotificationCell.Model
    static func shapeModel(_ cellModel: NotificationCell.Model) {
        if let user = cellModel.fromUser {
            cellModel.shapedDisplayName = shapeDisplayName(owner: cellModel.owner, user: user)
            // MEMO: MisskeyApiの "i/notifications"はfromUserの自己紹介を流してくれないので、対応するまで非表示にする
            
            //            if cellModel.type == .follow {
            //                let description = user.description ?? "自己紹介文はありません"
            //                cellModel.shapedDescritpion = shapeString(needReplyMark: false,
            //                                                          text: description,
            //                                                          emojis: user.emojis)
            //            }
        }
        
        if let myNote = cellModel.myNote {
            shapeModel(myNote)
        }
    }
    
    /// NoteCell.Modelを整形する
    /// - Parameter cellModel: NoteCell.Model
    static func shapeModel(_ cellModel: NoteCell.Model) {
        cellModel.shapedNote = shapeNote(cellModel)
        cellModel.shapedDisplayName = shapeDisplayName(cellModel)
        cellModel.shapedCw = shapedCw(cellModel)
        
        if let commentRNTarget = cellModel.commentRNTarget {
            commentRNTarget.shapedNote = shapeNote(commentRNTarget)
            commentRNTarget.shapedDisplayName = shapeDisplayName(commentRNTarget)
            commentRNTarget.shapedCw = shapedCw(commentRNTarget)
        }
    }
    
    /// NoteCell.Modelのうち、投稿を整形する
    /// - Parameter cellModel: NoteCell.Model
    private static func shapeNote(_ cellModel: NoteCell.Model) -> MFMString {
        return shapeString(owner: cellModel.owner, needReplyMark: cellModel.isReply, text: cellModel.noteEntity.note, emojis: cellModel.noteEntity.emojis)
    }
    
    private static func shapedCw(_ cellModel: NoteCell.Model) -> MFMString? {
        guard let cw = cellModel.noteEntity.cw else { return nil }
        var shaped = shapeString(owner: cellModel.owner, needReplyMark: cellModel.isReply, text: cw, emojis: cellModel.noteEntity.emojis)
        
        if let attributed = shaped.attributed {
            shaped.attributed = attributed + generatePlaneString(string: "\n > タップで詳細表示",
                                                                 font: UIFont(name: "Helvetica", size: 10.0) ?? .systemFont(ofSize: 10.0),
                                                                 textHex: "#808080")
        }
        
        return shaped
    }
    
    /// 任意の文字列を整形する
    /// - Parameters:
    ///   - needReplyMark: リプライマークがい必要か
    ///   - text: 任意の文字列
    ///   - emojis: 外インスタンスによるカスタム絵文字
    static func shapeString(owner: SecureUser?, needReplyMark: Bool, text: String, emojis: [EmojiModel?]?) -> MFMString {
        var textHex = Theme.shared.currentModel?.colorPattern.hex.text ?? "000000"
        textHex = "#\(textHex)"
        
        let replyHeader: NSMutableAttributedString = needReplyMark ? .getReplyMark() : .init() // リプライの場合は先頭にreplyマークつける
        let mfmString = text.mfmTransform(owner: owner,
                                          font: UIFont(name: "Helvetica", size: 11.0) ?? .systemFont(ofSize: 11.0),
                                          externalEmojis: emojis,
                                          lineHeight: 30,
                                          textHex: textHex)
        
        return MFMString(mfmEngine: mfmString.mfmEngine, attributed: replyHeader + (mfmString.attributed ?? .init()))
    }
    
    /// 名前を整形
    /// - Parameter cellModel: NoteCell.Model
    private static func shapeDisplayName(_ cellModel: NoteCell.Model) -> MFMString {
        return shapeDisplayName(owner: cellModel.owner, name: cellModel.noteEntity.displayName, username: cellModel.noteEntity.username, emojis: cellModel.noteEntity.emojis)
    }
    
    /// 名前を整形
    /// - Parameter user: UserEntity
    static func shapeDisplayName(owner: SecureUser?, user: UserEntity?) -> MFMString? {
        guard let user = user else { return nil }
        return shapeDisplayName(owner: owner, name: user.name, username: user.username, emojis: user.emojis)
    }
    
    /// 名前を整形
    /// - Parameters:
    ///   - name: String
    ///   - username: String
    ///   - emojis: 外インスタンスによるカスタム絵文字
    ///   - namefont:
    ///   - _usernameFont:
    ///   - nameHex:
    ///   - usernameColor:
    static func shapeDisplayName(owner: SecureUser?,
                                 name: String?,
                                 username: String?,
                                 emojis: [EmojiModel?]?,
                                 nameFont: UIFont? = nil,
                                 usernameFont _usernameFont: UIFont? = nil,
                                 nameHex: String? = nil,
                                 usernameColor: UIColor? = nil) -> MFMString {
        let displayName = name ?? ""
        let font = nameFont ?? UIFont(name: "Helvetica", size: 10.0) ?? .systemFont(ofSize: 10.0)
        
        var defaultTextHex = Theme.shared.currentModel?.colorPattern.hex.text ?? "000000"
        defaultTextHex = "#\(defaultTextHex)"
        
        let mfmString = displayName.mfmTransform(owner: owner,
                                                 font: font,
                                                 externalEmojis: emojis,
                                                 lineHeight: 25,
                                                 textHex: nameHex ?? defaultTextHex)
        
        let nameAttributed = mfmString.attributed ?? .init()
        let usernameAttributed = " @\(username ?? "")".getAttributedString(font: _usernameFont ?? usernameFont,
                                                                           color: usernameColor ?? Theme.shared.currentModel?.colorPattern.ui.sub0 ?? .darkGray)
        return MFMString(mfmEngine: mfmString.mfmEngine,
                         attributed: nameAttributed + usernameAttributed)
    }
    
    // MARK: Utilities
    
    /// Stringを適切なフォントを指定してNSAttributedStringに変換する
    /// - Parameters:
    ///   - string: 対象のstring
    ///   - font: フォント
    static func generatePlaneString(string: String, font: UIFont?, textHex: String? = nil) -> NSAttributedString {
        let fontName = font?.familyName ?? "Helvetica"
        let fontSize = font?.pointSize ?? 15.0
        
        return string.toAttributedString(family: fontName, size: fontSize, textHex: textHex) ?? .init()
    }
    
    /// カスタム絵文字のURLから画像データを取得し、非同期でsetされるようなUIImageViewを返す
    /// - Parameter imageUrl: 画像データのurl (アニメGIF / SVGも可)
    static func generateAsyncImageView(imageUrl: String, lineHeight: CGFloat = 30) -> UIImageView {
        let imageSize = lineHeight
        let imageView = MFMImageView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        
        imageView.backgroundColor = .lightGray
        imageView.frame = CGRect(x: 0, y: 0, width: imageSize, height: imageSize)
        imageView.sizeThatFits(.init(width: imageSize, height: imageSize))
        
        imageView.setImage(url: imageUrl)
        
        return imageView
    }
    
    // MARK: Pre-Transform
    
    /// リンク化する
    /// この時、urlに@が入ると後々hyperUserと干渉するので、
    /// @ → [at-mark.misscat.header] / # → [hash-tag.misscat.header] に変換しておく
    private static func hyperLink(_ text: String) -> String {
        // markdown link
        var result = text.replacingOccurrences(of: "\\[([^\\]]+)\\]\\(([^\\)]+)\\)",
                                               with: "<a style=\"color: [hash-tag.misscat.header]2F7CF6;\" href=\"$2\">$1</a>",
                                               options: .regularExpression)
        
        // normal Link
        let normalLink = "(https?://[\\w/:%#\\$&\\?\\(~\\.=\\+\\-@\"]+)"
        let targets = result.regexMatches(pattern: normalLink).map { $0[0] }.filter {
            $0.suffix(1) != "\"" // 上で処理されたものは弾く
        }
        
        // 先ににaタグに変換しておくと都合が良い
        targets.forEach { target in
            var to = target.replacingOccurrences(of: "@", with: "[at-mark.misscat.header]")
            to = to.replacingOccurrences(of: "#", with: "[hash-tag.misscat.header]")
            
            result = result.replacingOccurrences(of: target,
                                                 with: "<a style=\"color: [hash-tag.misscat.header]2F7CF6;\" href=\"\(to)\">\(to)</a>")
        }
        
        // mfm link (ex. <http~~>で、日本語を含めたリンク化ができるらしい)
        result = result.replacingOccurrences(of: "<<a", with: "<a").replacingOccurrences(of: "a>>", with: "a>")
        
        return result
    }
    
    /// MarkDownのため、文字列に修正を加える
    private static func markdown(_ text: String) -> String {
        let text = disablingTags(text)
        
        // bold
        let bold = text.replacingOccurrences(of: "\\*\\*([^\\*]+)\\*\\*",
                                             with: "<b>$1</b>",
                                             options: .regularExpression)
        
        // strike-through
        let strikeThrough = bold.replacingOccurrences(of: "~~([^\\~]+)~~",
                                                      with: "<s>$1</s>",
                                                      options: .regularExpression)
        
        // code-block
        let codeBlock = strikeThrough.replacingOccurrences(of: "```([^\\`]+)```",
                                                           with: "<span style=\"background-color:#272823;color:white;\">$1</span>",
                                                           options: .regularExpression)
        // code
        let code = codeBlock.replacingOccurrences(of: "`([^\\`]+)`",
                                                  with: "<span style=\"background-color:#272823;color:white;\">$1</span>",
                                                  options: .regularExpression)
        
        return code
    }
    
    /// 特定のタグを無効化していく
    private static func disablingTags(_ text: String) -> String {
        var result = text
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
    
    /// usernameをリンク化
    private static func hyperUser(_ text: String) -> String {
        return text.replacingOccurrences(of: "(@([a-zA-Z0-9]|\\.|_|@)+)",
                                         with: "<a style=\"color: [hash-tag.misscat.header]2F7CF6;\" href=\"http://tapEvents.misscat/$0\">$0</a>",
                                         options: .regularExpression)
    }
    
    /// ハッシュタグをリンク化
    private static func hyperHashtag(_ text: String) -> String {
        return text.replacingOccurrences(of: "(#[^(\\s|,)]+)",
                                         with: "<a style=\"color: [hash-tag.misscat.header]2F7CF6;\" href=\"http://hashtags.misscat/$0\">$0</a>",
                                         options: .regularExpression)
    }
    
    /// [at-mark.misscat.header], [hash-tag.misscat.header]を元に戻す
    private static func dehyperMagic(_ text: String) -> String {
        return text.replacingOccurrences(of: "[at-mark.misscat.header]", with: "@")
            .replacingOccurrences(of: "[hash-tag.misscat.header]", with: "#")
    }
}

// MARK: String Extension

// 装飾関係
extension String {
    /// カスタム絵文字以外のMFM処理を行う
    func mfmPreTransform() -> String {
        return MFMEngine.preTransform(string: self)
    }
    
    /// 主にカスタム絵文字に関するMFM処理を行う
    /// - Parameters:
    ///   - font: フォント
    ///   - externalEmojis: 外インスタンスのカスタム絵文字
    ///   - lineHeight: 文字の高さ
    func mfmTransform(owner: SecureUser?, font: UIFont, externalEmojis: [EmojiModel?]? = nil, lineHeight: CGFloat? = nil, textHex: String? = nil) -> MFMString {
        let mfm = MFMEngine(with: self, lineHeight: lineHeight)
        let mfmString = MFMString(mfmEngine: mfm, attributed: mfm.transform(owner: owner,
                                                                            font: font,
                                                                            externalEmojis: externalEmojis,
                                                                            textHex: textHex))
        
        return mfmString
    }
}

extension NoteModel {
    /// MFMEngineをラッピング・MFMの前処理を行う
    func mfmPreTransform() -> NoteModel {
        text = MFMEngine.preTransform(string: text ?? "")
        return self
    }
}
