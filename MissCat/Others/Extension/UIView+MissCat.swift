//
//  UIView+MissCat.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/20.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit
import RxSwift

extension UIView {
    
    func setTapGesture(_ disposeBag: DisposeBag, closure: @escaping ()->()) {
        let tapGesture = UITapGestureRecognizer()
        
        tapGesture.rx.event.bind{ _ in
            closure()
        }.disposed(by: disposeBag)
        
        self.isUserInteractionEnabled = true
        self.addGestureRecognizer(tapGesture)
    }
    
    func toImage(with view: UIView) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(view.bounds.size, view.isOpaque, 0.0)
        defer { UIGraphicsEndImageContext() }
        if let context = UIGraphicsGetCurrentContext() {
            view.layer.render(in: context)
            let image = UIGraphicsGetImageFromCurrentImageContext()
            return image
        }
        return nil
    }
    
    var parentViewController: UIViewController? {
        var parentResponder: UIResponder? = self
        while true {
            guard let nextResponder = parentResponder?.next else { return nil }
            if let viewController = nextResponder as? UIViewController {
                return viewController
            }
            parentResponder = nextResponder
        }
    }
    
    func getLabelWidth(text: String, font: UIFont) -> CGFloat {
        let label:UILabel = UILabel(frame: CGRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        label.numberOfLines = 0
        label.lineBreakMode = NSLineBreakMode.byWordWrapping
        label.font = font
        label.text = text + "AA" //微調整
        
        label.sizeToFit()
        return label.frame.width
    }
}
