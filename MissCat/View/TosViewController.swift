//
//  TosViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/31.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import UIKit

class TosViewController: UIViewController {
    var agreed: (() -> Void)?
    
    private var hasTapped: Bool = false
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(true)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        guard hasTapped else { return }
        agreed?()
    }
    
    @IBAction func tapped(_ sender: Any) {
        hasTapped = true
        navigationController?.popViewController(animated: true)
    }
}
