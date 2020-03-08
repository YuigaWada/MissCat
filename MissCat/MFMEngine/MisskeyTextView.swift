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
    public var xMargin: CGFloat = 10
    public var yMargin: CGFloat = 0
    
    open var attachmentList: [NSTextAttachment: YanagiText.Attachment] = [:]
    
    // MARK: Publics
    
    open func getViewString(with view: UIView, size: CGSize) -> NSAttributedString? {
        let yanagiAttachment = YanagiText.Attachment(view: view, size: size)
        
        let nsAttachment = NSTextAttachment()
        
        let fakeImageSize = CGSize(width: size.width + xMargin * 2, height: size.height + yMargin * 2)
        nsAttachment.image = generateFakeImage(size: fakeImageSize)
        
        register(nsAttachment, and: yanagiAttachment)
        
        return NSAttributedString(attachment: nsAttachment)
    }
    
    public func removeViewString(view: UIView, removeFromList: Bool = true) {
        view.removeFromSuperview()
        
        if removeFromList {
            attachmentList.forEach { ns, yanagi in
                guard yanagi.view === view else { return }
                self.attachmentList.removeValue(forKey: ns)
            }
        }
    }
    
    public func getAttachments() -> [NSTextAttachment: YanagiText.Attachment] {
        return attachmentList
    }
    
    public func addAttachment(ns: NSTextAttachment, yanagi: YanagiText.Attachment) {
        attachmentList[ns] = yanagi
    }
    
    public func resetViewString(resetList: Bool = true) {
        attachmentList.forEach { _, yanagi in
            yanagi.view.removeFromSuperview()
        }
        
        if resetList {
            attachmentList = [:]
        }
    }
    
    // MARK: Privates
    
    private func generateFakeImage(size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContext(size)
        
        let rect = CGRect(origin: .zero, size: size)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        context.setFillColor(UIColor.clear.cgColor)
        context.fill(rect)
        let fakeImage = UIGraphicsGetImageFromCurrentImageContext()
        
        UIGraphicsEndImageContext()
        
        return fakeImage
    }
    
    public func transformText() {
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
//            guard estimatedRect.origin.x.isFinite else { return }
            
            let lineHeight = estimatedRect.height
            
            estimatedRect.origin.y += lineHeight
            estimatedRect.origin.y -= yanagiAttachment.size.height
            
            estimatedRect.size = yanagiAttachment.size
            
            targetView.frame = estimatedRect
            
            if !self.subviews.contains(targetView) {
                self.addSubview(targetView)
            }
        })
    }
    
    open func register(_ nsAttachment: NSTextAttachment, and yanagiAttachment: YanagiText.Attachment) {
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
    
//
//    open func _textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
//
//        textView.attributedText.enumerateAttribute(NSAttributedString.Key.attachment, in: NSMakeRange(0, textView.attributedText.length), options: NSAttributedString.EnumerationOptions(rawValue: 0)) { [weak self] (value, viewStringRange, stop) in
//            guard let self = self, viewStringRange.location >= range.location else { return }
//
//            let currentSelectedRange = self.selectedRange
//            defer {
//                self.selectedRange = currentSelectedRange
//            }
//
//
//            let movement = text.count - range.length
//            let direction: CGFloat = movement > 0 ? 1 : -1
//
//            let nextLineRange = NSMakeRange(viewStringRange.location + movement, viewStringRange.length)
//
//            self.selectedRange = nextLineRange
//
//
//
//            guard let attachment = value as? NSTextAttachment,
//                let selectedTextRange = selectedTextRange,
//                let yanagiAttachment = self.findYanagiAttachment(nsAttachment: attachment) else { return }
//
//
//            let targetView = yanagiAttachment.view
//
//            let nextLineRect = self.firstRect(for: selectedTextRange)
//
//            let estimatedRect = CGRect(x: targetView.frame.origin.x + nextLineRect.width * direction,
//                                       y: targetView.frame.origin.y,
//                                       width: yanagiAttachment.size.width,
//                                       height: yanagiAttachment.size.height)
//
//
//            if text.isEmpty, NSEqualRanges(range, viewStringRange){
//                targetView.removeFromSuperview() // delete the target of View.
//            }
//            else {
//                targetView.frame = estimatedRect
//            }
//        }
//
//        return true
//    }
}

public extension YanagiText {
    struct Attachment {
        public var view: UIView
        public var size: CGSize
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
    
    public var isCached: Bool { // setされたcurrent〇〇Idについて、Cacheが存在するかどうか
        var count = 0
        
        if let currentNoteId = currentNoteId {
            count = noteAttachmentList[currentNoteId]?.count ?? 0
        }
        if let currentUserId = currentUserId {
            count = userAttachmentList[currentUserId]?.count ?? 0
        }
        
        return count != 0
    }
    
    // MARK: Ocverride
    
    // リンクタップのみ許可
    
    // FIX: 下の部分をコメントアウトしないと、XLPagerTabStripでスワイプできなくなる
    
    //    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    //        guard let position = closestPosition(to: point),
    //            let range = tokenizer.rangeEnclosingPosition(position, with: .character, inDirection: UITextDirection(rawValue: UITextLayoutDirection.left.rawValue)) else {
    //            return false
    //        }
    //        let startIndex = offset(from: beginningOfDocument, to: range.start)
    //        return attributedText.attribute(.link, at: startIndex, effectiveRange: nil) != nil
    //    }
    //
    //    override func becomeFirstResponder() -> Bool {
    //        return false
    //    }
    //
    
    // MARK: YanagiText Override
    
    //    override func register(_ nsAttachment: NSTextAttachment, and yanagiAttachment: YanagiText.Attachment) {
    //        super.register(nsAttachment, and: yanagiAttachment)
    //    }
    
    // MARK: Publics
    
    public func setId(noteId: String? = nil, userId: String? = nil) {
        currentNoteId = noteId
        currentUserId = userId
        
        showMFM()
    }
    
    public func showMFM() {
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
