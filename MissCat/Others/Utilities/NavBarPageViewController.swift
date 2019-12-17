//
//  NavBarPageViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/12/16.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit

class NavBarPageViewController: UIViewController {
    
    private var animator: UIViewPropertyAnimator?
    private var previousPositionX: CGFloat = 0
    
    
    
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if animator == nil {
            animator = self.generateAnimator()
        }
        
        guard let parent = self.parent, let touch = touches.first else { return }
        
        self.previousPositionX = touch.previousLocation(in: parent.view).x
    }
    
    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        
        guard let parent = self.parent, let touch = touches.first, let animator = animator else { return }
        let dx = touch.location(in: parent.view).x - self.previousPositionX
        let dxProportion: CGFloat = dx / self.view.frame.width
        
        
        let fractionComplete = animator.fractionComplete + dxProportion
        let frame = self.view.frame
        //        if 0 <= fractionComplete, fractionComplete <= 1 {
        //            animator.fractionComplete = fractionComplete
        self.view.frame = CGRect(x: frame.origin.x + dx,
                                 y: frame.origin.y,
                                 width: frame.width,
                                 height: frame.height)
        //        }
        //        else {
        //            //            print("animator.fractionComplete: \(animator.fractionComplete)\n new: \(touch.location(in: self.view).x), old: \(previousPositionX)\ndx:\(dxProportion)\nnew fractionComplete: \(fractionComplete)\ndxProportion: \(dxProportion)")
        //        }
        
        print("new: \(touch.location(in: parent.view).x), old: \(previousPositionX)\n")
    }
    
    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        
        guard let animator = animator else { return }
        let toClosing = animator.fractionComplete > 0.5
        animator.isReversed = !toClosing
        
        animator.addCompletion { _ in
            guard toClosing else { return }
            self.animator = nil
        }
        
        animator.startAnimation()
    }
    
    
    private func generateAnimator()-> UIViewPropertyAnimator {
        return .init(duration: 1.0, curve: .easeInOut){
            let frame = self.view.frame
            
            self.view.frame = CGRect(x: frame.width,
                                     y: frame.origin.y,
                                     width: frame.width,
                                     height: frame.height)
        }
        
    }
}

extension UIScrollView {
    override open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.superview?.touchesBegan(touches, with: event)
        
        super.touchesBegan(touches, with: event)
    }
    
    override open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.superview?.touchesMoved(touches, with: event)
        super.touchesMoved(touches, with: event)
    }
    
    override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.superview?.touchesEnded(touches, with: event)
        super.touchesEnded(touches, with: event)
    }
}
