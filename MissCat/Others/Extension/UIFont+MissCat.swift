//
//  UIFont+MissCat.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/12/02.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit

extension UIFont {
    static func awesomeSolid(fontSize: CGFloat) -> UIFont? {
        return UIFont(name: "FontAwesome5Free-Solid", size: fontSize)
    }
    
    static func awesomeRegular(fontSize: CGFloat) -> UIFont? {
        return UIFont(name: "FontAwesome5Free-Regular", size: fontSize)
    }
    
    static func awesomeBrand(fontSize: CGFloat) -> UIFont? {
        return UIFont(name: "FontAwesome5Brands-Regular", size: fontSize)
    }
}
