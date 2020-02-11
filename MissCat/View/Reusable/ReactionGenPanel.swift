//
//  ReactionGenPanel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/12/05.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import FloatingPanel

public class ReactionGenPanel: FloatingPanelController, ReactionGenViewControllerDelegate {
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        surfaceView.cornerRadius = 12
        isRemovalInteractionEnabled = true // Optional: Let it removable by a swipe-down
    }
    
    // MARK: ReactionGenViewControllerDelegate
    
    public func scrollUp() {
        move(to: .full, animated: true)
    }
}

// MARK: Layout

public class MissCatFloatingPanelLayout: FloatingPanelLayout {
    public var initialPosition: FloatingPanelPosition {
        return .half
    }
    
    public func insetFor(position: FloatingPanelPosition) -> CGFloat? {
        switch position {
        case .full: return 16.0 // A top inset from safe area
        case .half: return 330 // A bottom inset from the safe area
        case .tip: return nil
        default: return nil // Or `case .hidden: return nil`
        }
    }
    
    public func backdropAlphaFor(position: FloatingPanelPosition) -> CGFloat {
        return 0.5
    }
}

public class MissCatFloatingPanelStocksBehavior: FloatingPanelBehavior {
    public func shouldProjectMomentum(_ fpc: FloatingPanelController, for proposedTargetPosition: FloatingPanelPosition) -> Bool {
        return true
    }
}
