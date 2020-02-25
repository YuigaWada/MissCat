//
//  ReactionCollectionHeader.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/02/25.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import UIKit

public class ReactionCollectionHeader: UICollectionViewCell {
    @IBOutlet weak var headerTitleLabel: UILabel!
    
    public func setTitle(_ name: String) {
        headerTitleLabel.text = name
    }
}
