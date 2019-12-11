//
//  RenoteeCell.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/20.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit

public class RenoteeCell: UITableViewCell {

    @IBOutlet weak var renoteMarkLabel: UILabel!
    @IBOutlet weak var renoteeLabel: UILabel!
    
    private var renotee: String? {
        didSet {
            guard let renotee = renotee else { renoteeLabel.text = nil; return }
            renoteeLabel.text = renotee + "さんがRenoteしました"
        }
    }
    
    
    public override func layoutSubviews() {
        self.setupComponent()
    }
    
    private func setupComponent() {
        self.renoteMarkLabel.font = .awesomeSolid(fontSize: 15.0)
    }
    
    public func setRenotee(_ renotee: String?) {
        self.renotee = renotee
    }
    
}
