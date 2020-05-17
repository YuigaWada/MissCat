//
//  MissCatImageView.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/05/17.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import UIKit

class MissCatImageView: UIImageView {
    private var isCircle: Bool = false
    
    /// 円を描くようにフラグを建てる
    func maskCircle() {
        isCircle = true
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        if isCircle { layer.cornerRadius = frame.width / 2 }
    }
}
