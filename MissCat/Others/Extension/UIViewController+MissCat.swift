//
//  UIViewController+missCat.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/17.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit
import RxSwift
import FloatingPanel

extension UIViewController {
    
    //MARK: Present
    func presentOnFullScreen(_ viewControllerToPresent: UIViewController, animated: Bool, completion: (()->Void)?) {
        let vc = viewControllerToPresent
        vc.modalPresentationStyle = .fullScreen
        
        self.present(vc, animated: animated, completion: completion)
    }
    
    func move2ViewController(identifier: String) {
        guard let storyboard = self.storyboard else { return }
        
        let target = storyboard.instantiateViewController(withIdentifier: identifier)
        self.presentOnFullScreen(target, animated: true, completion: nil)
    }
    
    func getSafeAreaSize()-> (width: CGFloat, height: CGFloat) {
        var bottomPadding: CGFloat = 0
        var leftPadding: CGFloat = 0
        var rightPadding: CGFloat = 0
        
        if #available(iOS 11.0, *) {
            let window = UIApplication.shared.keyWindow
            bottomPadding = window!.safeAreaInsets.bottom
            leftPadding = window!.safeAreaInsets.left
            rightPadding = window!.safeAreaInsets.right
        }
        
        return (width: leftPadding + rightPadding, height: bottomPadding) // portrait
    }
    
    func getFooterTabSize(height: CGFloat)-> CGRect {
        let (width: notSafeWidth, height: notSafeHeight) = self.getSafeAreaSize()
        
        return CGRect(x: 0,
                      y: self.view.frame.height - height - notSafeHeight,
                      width: self.view.frame.width - notSafeWidth,
                      height:  height)
    }
    
}

extension UIViewController: FloatingPanelControllerDelegate {
    func presentWithSemiModal(_ viewControllerToPresent: UIViewController, animated: Bool, completion: (()->Void)?) {
        let reactionGenPanel = ReactionGenPanel()
        
        reactionGenPanel.delegate = self
        reactionGenPanel.set(contentViewController: viewControllerToPresent)
        self.present(reactionGenPanel, animated: true, completion: nil)
        
        guard let contentVC = viewControllerToPresent as? ReactionGenViewController else { return }
        contentVC.delegate = reactionGenPanel
    }
    
    public func floatingPanel(_ vc: FloatingPanelController, layoutFor newCollection: UITraitCollection) -> FloatingPanelLayout? {
        return MissCatFloatingPanelLayout()
    }
    
    public func floatingPanel(_ vc: FloatingPanelController, behaviorFor newCollection: UITraitCollection) -> FloatingPanelBehavior? {
        return MissCatFloatingPanelStocksBehavior()
    }
    
    public func floatingPanelWillBeginDragging(_ vc: FloatingPanelController) {
        vc.view.endEditing(true)
    }
    
    //　半モーダルを下へスワイプした時FloatingPanelControllerを消す
    public func floatingPanelDidEndDragging(_ fpc: FloatingPanelController, withVelocity velocity: CGPoint, targetPosition: FloatingPanelPosition) {
        guard targetPosition == .tip else { return }
        
        fpc.dismiss(animated: true, completion: nil)
    }
}