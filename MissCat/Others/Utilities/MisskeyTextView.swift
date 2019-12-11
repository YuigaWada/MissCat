//
//  MisskeyTextView.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/23.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit

// リンクタップのみできるTextView
class MisskeyTextView: UITextView {

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard let position = closestPosition(to: point),
            let range = tokenizer.rangeEnclosingPosition(position, with: .character, inDirection: UITextDirection(rawValue: UITextLayoutDirection.left.rawValue)) else {
                return false
        }
        let startIndex = offset(from: beginningOfDocument, to: range.start)
        return attributedText.attribute(.link, at: startIndex, effectiveRange: nil) != nil
    }
    
    override func becomeFirstResponder() -> Bool {
        return false
    }
}
