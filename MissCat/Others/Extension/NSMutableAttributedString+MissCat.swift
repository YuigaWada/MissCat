//
//  NSMutableAttributedString+MissCat.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/24.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit

extension NSMutableAttributedString {
    static func getReplyMark() -> NSMutableAttributedString {
        let attribute: [NSAttributedString.Key: Any] = [.font: UIFont.awesomeSolid(fontSize: 15.0) ?? UIFont.systemFont(ofSize: 15.0),
                                                        .foregroundColor: UIColor.lightGray]
        let replyMark = NSMutableAttributedString(string: "reply ", attributes: attribute)
        
        return replyMark
    }
}

extension NSAttributedString {
    static func + (left: NSAttributedString, right: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(left)
        result.append(right)
        return result
    }
    
    func changeColor(to color: UIColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(self)
        
        let range = NSRange(location: 0, length: string.count)
        result.addAttribute(NSAttributedString.Key.foregroundColor, value: color, range: range)
        
        return result
    }
}
