//
//  ReactionGenPanel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/12/05.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import FloatingPanel

class ReactionGenPanel: FloatingPanelController, ReactionGenViewControllerDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        surfaceView.cornerRadius = 12
        isRemovalInteractionEnabled = true // Optional: Let it removable by a swipe-down
    }
    
    // MARK: ReactionGenViewControllerDelegate
    
    func scrollUp() {
        move(to: .full, animated: true)
    }
}

// MARK: Layout

class MissCatFloatingPanelLayout: FloatingPanelLayout {
    var initialPosition: FloatingPanelPosition {
        return .half
    }
    
    func insetFor(position: FloatingPanelPosition) -> CGFloat? {
        switch position {
        case .full: return 16.0 // A top inset from safe area
        case .half: return 330 // A bottom inset from the safe area
        case .tip: return nil
        default: return nil // Or `case .hidden: return nil`
        }
    }
    
    func backdropAlphaFor(position: FloatingPanelPosition) -> CGFloat {
        return 0.5
    }
}

class MissCatFloatingPanelStocksBehavior: FloatingPanelBehavior {
    func shouldProjectMomentum(_ fpc: FloatingPanelController, for proposedTargetPosition: FloatingPanelPosition) -> Bool {
        return true
    }
}
