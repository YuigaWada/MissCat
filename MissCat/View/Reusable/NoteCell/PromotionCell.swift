//
//  PromotionCell.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/10.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import UIKit

class PromotionCell: UITableViewCell {
    @IBOutlet weak var iconLabel: UILabel!
    @IBOutlet weak var promotionLabel: UILabel!
    
    private lazy var mainColor: UIColor = .init(hex: "d28a3f")
    
    override func layoutSubviews() {
        setupComponent()
    }
    
    private func setupComponent() {
        iconLabel.font = .awesomeSolid(fontSize: 15.0)
        iconLabel.textColor = mainColor
        promotionLabel.textColor = mainColor
        backgroundColor = Theme.shared.currentModel?.colorPattern.ui.base ?? .white
    }
}
