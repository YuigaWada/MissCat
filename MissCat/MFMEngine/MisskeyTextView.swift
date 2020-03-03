//
//  MisskeyTextView.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/23.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit
import YanagiText

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
        
        attachmentList = [:]
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
