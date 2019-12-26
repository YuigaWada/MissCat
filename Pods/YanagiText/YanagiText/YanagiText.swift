//
//  YanagiText.swift
//  YanagiText
//
//  Created by Yuiga Wada on 2019/12/24.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit

open class YanagiText: UITextView {
    
    public var xMargin: CGFloat = 10
    public var yMargin: CGFloat = 0
    
    private var attachmentList: Dictionary<NSTextAttachment,YanagiText.Attachment> = [:]
    
    //MARK: Override
    override open var attributedText: NSAttributedString! {
        didSet {
            DispatchQueue.main.async {
                self.transformText()
            }
        }
    }
    
    //MARK: Publics
    public func getViewString(with view: UIView, size: CGSize)-> NSAttributedString? {
        let yanagiAttachment = YanagiText.Attachment(view: view, size: size)
        
        let nsAttachment = NSTextAttachment()
        
        let fakeImageSize = CGSize(width: size.width + xMargin * 2, height: size.height + yMargin * 2)
        nsAttachment.image = self.generateFakeImage(size: fakeImageSize)
        
        self.register(nsAttachment, and: yanagiAttachment)
        
        return NSAttributedString(attachment: nsAttachment)
    }
    
    public func removeViewString(view: UIView, removeFromList: Bool = true) {
        view.removeFromSuperview()
        
        if removeFromList {
            self.attachmentList.forEach { ns, yanagi in
                guard yanagi.view === view else { return }
                self.attachmentList.removeValue(forKey: ns)
            }
        }
    }
    
    public func getAttachments()-> Dictionary<NSTextAttachment,YanagiText.Attachment> {
        return self.attachmentList
    }
    
    public func addAttachment(ns: NSTextAttachment, yanagi: YanagiText.Attachment) {
        self.attachmentList[ns] = yanagi
    }
    
    
    public func resetViewString(resetList: Bool = true) {
        self.attachmentList.forEach { ns, yanagi in
            yanagi.view.removeFromSuperview()
        }
        
        if resetList {
            self.attachmentList = [:]
        }
    }
    
    //MARK: Privates
    
    private func generateFakeImage(size: CGSize)-> UIImage? {
        UIGraphicsBeginImageContext(size)
        
        let rect = CGRect(origin: .zero, size: size)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        context.setFillColor(UIColor.clear.cgColor)
        context.fill(rect)
        let fakeImage = UIGraphicsGetImageFromCurrentImageContext()
        
        UIGraphicsEndImageContext()
        
        return fakeImage
    }
    
    private func transformText() {
        self.attributedText.enumerateAttribute(.attachment, in: NSMakeRange(0, self.attributedText.length), options: .longestEffectiveRangeNotRequired, using: { [weak self] value, range, _ in
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
    
    private func register(_ nsAttachment: NSTextAttachment, and yanagiAttachment: YanagiText.Attachment) {
        self.attachmentList[nsAttachment] = yanagiAttachment
    }
    
    private func findYanagiAttachment(nsAttachment: NSTextAttachment)-> YanagiText.Attachment? {
        
        var result: YanagiText.Attachment?
        attachmentList.forEach{ key, value in
            guard key === nsAttachment else { return }
            result = value
        }
        
        return result
    }
    
    
    
    open func shouldChangeText(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        
        textView.attributedText.enumerateAttribute(NSAttributedString.Key.attachment, in: NSMakeRange(0, textView.attributedText.length), options: NSAttributedString.EnumerationOptions(rawValue: 0)) { [weak self] (value, viewStringRange, stop) in
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
            
            
            if text.isEmpty, NSEqualRanges(range, viewStringRange){
                targetView.removeFromSuperview() // delete the target of View.
            }
            else {
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
        var view: UIView
        var size: CGSize
    }
}

internal extension CGRect {
    var center: CGPoint {
        return CGPoint(x: self.origin.x + self.width / 2,
                       y: self.origin.y + self.height / 2)
    }
}


