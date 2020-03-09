//
//  NotificationCellModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/24.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit

public class NotificationCellModel {
    public func shapeNote(note: String, isReply: Bool) -> NSAttributedString? {
        let replyHeader: NSMutableAttributedString = isReply ? .getReplyMark() : .init() // リプライの場合は先頭にreplyマークつける
        let body = MFMEngine.generatePlaneString(string: note, font: UIFont(name: "Helvetica", size: 11.0))
        
        return replyHeader + body
    }
}
