//
//  UIView+MissCat.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/20.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import RxCocoa
import RxSwift
import UIKit

extension UIView {
    var rxTap: ControlEvent<UITapGestureRecognizer> {
        let tapGesture = UITapGestureRecognizer()
        
        isUserInteractionEnabled = true
        addGestureRecognizer(tapGesture)
        return tapGesture.rx.event
    }
    
    func setTapGesture(_ disposeBag: DisposeBag, closure: @escaping () -> Void) {
        let tapGesture = UITapGestureRecognizer()
        
        tapGesture.rx.event.bind { _ in
            closure()
        }.disposed(by: disposeBag)
        
        isUserInteractionEnabled = true
        addGestureRecognizer(tapGesture)
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
        let label: UILabel = UILabel(frame: CGRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        label.numberOfLines = 0
        label.lineBreakMode = NSLineBreakMode.byWordWrapping
        label.font = font
        label.text = text
        
        label.sizeToFit()
        return label.frame.width
    }
    
    func deselectCell(on tableView: UITableView) {
        guard let indexPathForSelectedRow = tableView.indexPathForSelectedRow else { return }
        tableView.deselectRow(at: indexPathForSelectedRow, animated: true)
    }
    
    // MARK: Vibrate
    
    func vibrated(vibrated: Bool, view: UIView, radians: Float = 5.0, duration: Double = 0.05) {
        if vibrated {
            let animation = CABasicAnimation(keyPath: "transform.rotation")
            
            animation.duration = duration
            animation.fromValue = degreesToRadians(radians)
            animation.toValue = degreesToRadians(radians * (-1))
            animation.repeatCount = Float.infinity
            animation.autoreverses = true
            view.layer.add(animation, forKey: "VibrateAnimationKey")
        } else {
            view.layer.removeAnimation(forKey: "VibrateAnimationKey")
        }
    }
    
    private func degreesToRadians(_ degrees: Float) -> Float {
        return degrees * Float(Double.pi) / 180.0
    }
}
