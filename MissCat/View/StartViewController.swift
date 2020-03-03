//
//  StartViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/02.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import UIKit

public class StartViewController: UIViewController {
    @IBOutlet weak var logoImageView: UIImageView!
    @IBOutlet weak var phraseLabel: UILabel!
    
    @IBOutlet weak var instanceLabel: UILabel!
    
    @IBOutlet weak var startingButton: UIButton!
    @IBOutlet weak var changeInstanceButton: UIButton!
    
    private lazy var components = [phraseLabel, instanceLabel, startingButton, changeInstanceButton]
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setGradientLayer()
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hideComponents()
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        summon(after: false)
        super.viewDidAppear(animated)
        
        UIView.animate(withDuration: 0.7, delay: 0, options: .curveEaseInOut, animations: {
            self.summon(after: true)
        }, completion: nil)
    }
    
    private func setGradientLayer() {
        let gradientLayer: CAGradientLayer = CAGradientLayer()
        
        gradientLayer.colors = [UIColor(hex: "4691a3").cgColor,
                                UIColor(hex: "5AB0C5").cgColor,
                                UIColor(hex: "89d5e8").cgColor]
        gradientLayer.frame = view.bounds
        gradientLayer.startPoint = CGPoint(x: 0, y: 1)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0)
        
        view.layer.insertSublayer(gradientLayer, at: 0)
    }
    
    private func hideComponents() {
        components.forEach { $0?.alpha = 0 }
    }
    
    /// Label, Buttton, Image等をすべて上からフェードインさせる処理
    /// - Parameter after: フェードイン前かフェードイン後か
    private func summon(after: Bool = false) {
        let sign = after ? 1 : -1
        components.forEach {
            guard let comp = $0 else { return }
            comp.alpha = after ? 1 : 0
            let originalFrame = comp.frame
            
            comp.frame = CGRect(x: originalFrame.origin.x,
                                y: originalFrame.origin.y + CGFloat(30 * sign),
                                width: originalFrame.width,
                                height: originalFrame.height)
        }
    }
}
