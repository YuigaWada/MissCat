//
//  RenoteeCell.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/20.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit

class RenoteeCell: UITableViewCell {
    @IBOutlet weak var renoteMarkLabel: UILabel!
    @IBOutlet weak var renoteeLabel: UILabel!
    
    private var renotee: String? {
        didSet {
            guard let renotee = renotee else { renoteeLabel.text = nil; return }
            renoteeLabel.text = renotee + "さんがRenoteしました"
        }
    }
    
    override func layoutSubviews() {
        setupComponent()
    }
    
    private func setupComponent() {
        renoteMarkLabel.font = .awesomeSolid(fontSize: 13.0)
        backgroundColor = Theme.shared.currentModel?.colorPattern.ui.base ?? .white
        renoteMarkLabel.textColor = Theme.shared.currentModel?.colorPattern.ui.text ?? .black
        renoteeLabel.textColor = Theme.shared.currentModel?.colorPattern.ui.text ?? .black
    }
    
    func setRenotee(_ renotee: String?) {
        self.renotee = renotee
    }
}
