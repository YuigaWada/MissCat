//
//  MisskeyTextView.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/23.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit

// MARK: YanagiText

open class YanagiText: UITextView {
    var xMargin: CGFloat = 0
    var yMargin: CGFloat = 0
    
    var attachmentList: [NSTextAttachment: YanagiText.Attachment] = [:]
    
    // MARK: Publics
    
    open func getViewString(with view: UIView, size: CGSize) -> NSAttributedString? {
        let yanagiAttachment = YanagiText.Attachment(view: view, size: size)
        
        let nsAttachment = NSTextAttachment()
        
        let fakeImageSize = CGSize(width: size.width + xMargin * 2, height: size.height + yMargin * 2)
        nsAttachment.image = YanagiText.generateFakeImage(size: fakeImageSize)
        
        register(nsAttachment, and: yanagiAttachment)
        
        return NSAttributedString(attachment: nsAttachment)
    }
    
    static func getAttachmentString(size: CGSize) -> (attributedString: NSAttributedString?, attachment: NSTextAttachment) {
        let nsAttachment = NSTextAttachment()
        let fakeImageSize = CGSize(width: size.width, height: size.height)
        
        nsAttachment.image = YanagiText.generateFakeImage(size: fakeImageSize)
        
        return (attributedString: NSAttributedString(attachment: nsAttachment), attachment: nsAttachment)
    }
    
    func removeViewString(view: UIView, removeFromList: Bool = true) {
        view.removeFromSuperview()
        
        if removeFromList {
            attachmentList.forEach { ns, yanagi in
                guard yanagi.view === view else { return }
                self.attachmentList.removeValue(forKey: ns)
            }
        }
    }
    
    func getAttachments() -> [NSTextAttachment: YanagiText.Attachment] {
        return attachmentList
    }
    
    func addAttachment(ns: NSTextAttachment, yanagi: YanagiText.Attachment) {
        attachmentList[ns] = yanagi
    }
    
    func resetViewString(resetList: Bool = true) {
        attachmentList.forEach { _, yanagi in
            yanagi.view.removeFromSuperview()
        }
        
        if resetList {
            attachmentList = [:]
        }
    }
    
    // MARK: Privates
    
    private static func generateFakeImage(size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContext(size)
        
        let rect = CGRect(origin: .zero, size: size)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        context.setFillColor(UIColor.clear.cgColor)
        context.fill(rect)
        let fakeImage = UIGraphicsGetImageFromCurrentImageContext()
        
        UIGraphicsEndImageContext()
        
        return fakeImage
    }
    
    func renderViewStrings() {
        attachmentList.values.forEach { target in
            guard !self.subviews.contains(target.view) else { return }
            self.addSubview(target.view)
        }
    }
    
    func transformText() {
        layoutIfNeeded()
        attributedText.enumerateAttribute(.attachment, in: NSMakeRange(0, attributedText.length), options: .longestEffectiveRangeNotRequired, using: { [weak self] value, range, _ in
            guard let self = self else { return }
            
            defer {
                self.selectedRange = NSMakeRange(0, 0)
            }
            
            self.selectedRange = range
            
            guard let attachment = value as? NSTextAttachment,
                  let yanagiAttachment = self.findYanagiAttachment(nsAttachment: attachment),
                  let selectedTextRange = self.selectedTextRange else { return }
            
            let targetView = yanagiAttachment.view
            
            var estimatedRect = self.firstRect(for: selectedTextRange).insetBy(dx: xMargin, dy: yMargin)
            print(estimatedRect)
            guard estimatedRect.origin.x.isFinite else { return }
            
            let lineHeight = estimatedRect.height
            
            estimatedRect.origin.y += lineHeight
            estimatedRect.origin.y -= yanagiAttachment.size.height
            
            estimatedRect.size = yanagiAttachment.size
            
            targetView.frame = estimatedRect
        })
    }
    
    func register(_ nsAttachment: NSTextAttachment, and yanagiAttachment: YanagiText.Attachment) {
        attachmentList[nsAttachment] = yanagiAttachment
    }
    
    private func findYanagiAttachment(nsAttachment: NSTextAttachment) -> YanagiText.Attachment? {
        var result: YanagiText.Attachment?
        attachmentList.forEach { key, value in
            guard key === nsAttachment else { return }
            result = value
        }
        
        return result
    }
    
    open func shouldChangeText(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        textView.attributedText.enumerateAttribute(NSAttributedString.Key.attachment, in: NSMakeRange(0, textView.attributedText.length), options: NSAttributedString.EnumerationOptions(rawValue: 0)) { [weak self] value, viewStringRange, _ in
            guard let self = self, viewStringRange.location >= range.location else { return }
            
            let currentSelectedRange = self.selectedRange
            defer {
                self.selectedRange = currentSelectedRange
            }
            
            let nextLineRange = NSMakeRange(viewStringRange.location, viewStringRange.length)
            
            self.selectedRange = nextLineRange
            
            guard let attachment = value as? NSTextAttachment,
                  let selectedTextRange = selectedTextRange,
                  let yanagiAttachment = self.findYanagiAttachment(nsAttachment: attachment) else { return }
            
            let targetView = yanagiAttachment.view
            
            var estimatedRect = self.firstRect(for: selectedTextRange).insetBy(dx: xMargin, dy: yMargin)
            let lineHeight = estimatedRect.height
            
            estimatedRect.origin.y += lineHeight
            estimatedRect.origin.y -= yanagiAttachment.size.height
            
            estimatedRect.size = yanagiAttachment.size
            
            if text.isEmpty, NSEqualRanges(range, viewStringRange) {
                targetView.removeFromSuperview() // delete the target of View.
            } else {
                targetView.frame = estimatedRect
            }
        }
        
        return true
    }
}

extension YanagiText {
    struct Attachment {
        var view: UIView
        var size: CGSize
    }
}

internal extension CGRect {
    var center: CGPoint {
        return CGPoint(x: origin.x + width / 2,
                       y: origin.y + height / 2)
    }
}

// MARK: MisskeyTextView

private typealias AttachmentDic = [NSTextAttachment: YanagiText.Attachment]

// リンクタップのみできるTextView
// idに対してattachmentを保存できるようなYanagiText
class MisskeyTextView: YanagiText {
    override var attachmentList: [NSTextAttachment: YanagiText.Attachment] {
        didSet {
            guard !isRefreshing else { return }
            
            // noteId或いはusreIdに対してattachmentの情報をsaveしておく
            if let currentNoteId = currentNoteId {
                noteAttachmentList[currentNoteId] = attachmentList
            }
            if let currentUserId = currentUserId {
                userAttachmentList[currentUserId] = attachmentList
            }
        }
    }
    
    private var isRefreshing: Bool = false
    private var currentNoteId: String?
    private var currentUserId: String?
    
    private var noteAttachmentList: [String: AttachmentDic] = [:]
    private var userAttachmentList: [String: AttachmentDic] = [:]
    
    var isCached: Bool { // setされたcurrent〇〇Idについて、Cacheが存在するかどうか
        var count = 0
        
        if let currentNoteId = currentNoteId {
            count = noteAttachmentList[currentNoteId]?.count ?? 0
        }
        if let currentUserId = currentUserId {
            count = userAttachmentList[currentUserId]?.count ?? 0
        }
        
        return count != 0
    }
    
    // MARK: Override
    
    // https://stackoverflow.com/questions/36198299/uitextview-disable-selection-allow-links/44878203#comment99895928_44878203
    
    // リンクタップのみ許可する
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event),
              let position = closestPosition(to: point),
              let range = tokenizer.rangeEnclosingPosition(position, with: .character, inDirection: UITextDirection(rawValue: UITextLayoutDirection.left.rawValue))
        else {
            return false
        }
        let startIndex = offset(from: beginningOfDocument, to: range.start)
        return attributedText.attribute(.link, at: startIndex, effectiveRange: nil) != nil
    }
    
    // 選択時のメニュー(コピー・ペースト等)が出ないようにする
    override func becomeFirstResponder() -> Bool {
        return false
    }
    
    // MARK: Publics
    
    func setId(noteId: String? = nil, userId: String? = nil) {
        currentNoteId = noteId
        currentUserId = userId
        
//        showMFM()
    }
    
    func showMFM() {
        isRefreshing = true
        defer {
            self.isRefreshing = false
        }
        
        refreshAttachmentState(isHidden: true)
        
        attachmentList = [:] // 初期化
        if let currentNoteId = currentNoteId, let nextAttachmentList = noteAttachmentList[currentNoteId] {
            attachmentList = nextAttachmentList
        } else if let currentUserId = currentUserId, let nextAttachmentList = userAttachmentList[currentUserId] {
            attachmentList = nextAttachmentList
        } else {
            return
        }
        
        refreshAttachmentState(isHidden: false)
    }
    
    private func refreshAttachmentState(isHidden: Bool) {
        attachmentList.forEach { _, attachment in
            attachment.view.isHidden = isHidden
        }
    }
}
