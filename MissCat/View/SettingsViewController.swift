//
//  SettingsViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/12.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import UIKit

public class SettingsViewController: UITableViewController {
    public override func viewDidLoad() {
        super.viewDidLoad()
        setFont()
    }
    
    private func setFont() {
        for i in 0 ... 6 {
            guard let iconLabel = view.viewWithTag(i) as? UILabel else { return }
            iconLabel.font = .awesomeSolid(fontSize: 15.0)
        }
    }
}
