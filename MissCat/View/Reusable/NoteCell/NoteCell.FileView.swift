//
//  NoteCell.FileView.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/22.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import UIKit

extension NoteCell {
    public enum FileType {
        case PlaneImage
        case GIFImage
        case Video
        case Audio
        case Unknown
    }
    
    public class FileView: UIImageView {
        private var playIconImageView: UIImageView?
        private var nsfwCover: UIView?
        
        public func setPlayIconImage(hide: Bool = false) {
            let parentView = self
            guard playIconImageView == nil, !hide else {
                playIconImageView?.isHidden = hide; return
            }
            
            guard let playIconImage = UIImage(named: "play") else { return }
            let playIconImageView = UIImageView(image: playIconImage)
            
            let edgeMultiplier: CGFloat = 0.4
            
            parentView.layoutIfNeeded()
            let parentFrame = parentView.frame
            let edge = min(parentFrame.width, parentFrame.height) * edgeMultiplier
            
            playIconImageView.alpha = 0.7
            playIconImageView.center = parentView.center
            playIconImageView.frame = CGRect(x: playIconImageView.frame.origin.x,
                                             y: playIconImageView.frame.origin.y,
                                             width: edge,
                                             height: edge)
            
            playIconImageView.translatesAutoresizingMaskIntoConstraints = false
            parentView.addSubview(playIconImageView)
            
            parentView.addConstraints([
                NSLayoutConstraint(item: playIconImageView,
                                   attribute: .width,
                                   relatedBy: .equal,
                                   toItem: parentView,
                                   attribute: .width,
                                   multiplier: 0,
                                   constant: edge),
                
                NSLayoutConstraint(item: playIconImageView,
                                   attribute: .height,
                                   relatedBy: .equal,
                                   toItem: parentView,
                                   attribute: .height,
                                   multiplier: 0,
                                   constant: edge),
                
                NSLayoutConstraint(item: playIconImageView,
                                   attribute: .centerX,
                                   relatedBy: .equal,
                                   toItem: parentView,
                                   attribute: .centerX,
                                   multiplier: 1.0,
                                   constant: 0),
                
                NSLayoutConstraint(item: playIconImageView,
                                   attribute: .centerY,
                                   relatedBy: .equal,
                                   toItem: parentView,
                                   attribute: .centerY,
                                   multiplier: 1.0,
                                   constant: 0)
            ])
            
            self.playIconImageView = playIconImageView
        }
        
        public func setNSFW(hide: Bool = false) {
            guard nsfwCover == nil, !hide else {
                nsfwCover?.isHidden = hide; return
            }
            
            let parentView = self
            parentView.layoutIfNeeded()
            
            // coverView
            let coverView = UIView()
            let parentFrame = parentView.frame
            coverView.backgroundColor = .clear
            coverView.frame = parentFrame
            coverView.translatesAutoresizingMaskIntoConstraints = false
            parentView.addSubview(coverView)
            
            // すりガラス
            let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
            blurView.translatesAutoresizingMaskIntoConstraints = false
            coverView.addSubview(blurView)
            
            // label: 閲覧注意 タップで表示
            let nsfwLabel = UILabel()
            nsfwLabel.text = "閲覧注意\nタップで表示"
            nsfwLabel.center = parentView.center
            nsfwLabel.textAlignment = .center
            nsfwLabel.numberOfLines = 2
            nsfwLabel.textColor = .init(hex: "FFFF8F")
            
            nsfwLabel.translatesAutoresizingMaskIntoConstraints = false
            coverView.addSubview(nsfwLabel)
            
            // AutoLayout
            parentView.addConstraints([
                NSLayoutConstraint(item: coverView,
                                   attribute: .width,
                                   relatedBy: .equal,
                                   toItem: parentView,
                                   attribute: .width,
                                   multiplier: 1.0,
                                   constant: 0),
                
                NSLayoutConstraint(item: coverView,
                                   attribute: .height,
                                   relatedBy: .equal,
                                   toItem: parentView,
                                   attribute: .height,
                                   multiplier: 1.0,
                                   constant: 0),
                
                NSLayoutConstraint(item: coverView,
                                   attribute: .centerX,
                                   relatedBy: .equal,
                                   toItem: parentView,
                                   attribute: .centerX,
                                   multiplier: 1.0,
                                   constant: 0),
                
                NSLayoutConstraint(item: coverView,
                                   attribute: .centerY,
                                   relatedBy: .equal,
                                   toItem: parentView,
                                   attribute: .centerY,
                                   multiplier: 1.0,
                                   constant: 0)
            ])
            
            coverView.addConstraints([
                NSLayoutConstraint(item: blurView,
                                   attribute: .width,
                                   relatedBy: .equal,
                                   toItem: coverView,
                                   attribute: .width,
                                   multiplier: 1.0,
                                   constant: 0),
                
                NSLayoutConstraint(item: blurView,
                                   attribute: .height,
                                   relatedBy: .equal,
                                   toItem: coverView,
                                   attribute: .height,
                                   multiplier: 1.0,
                                   constant: 0),
                
                NSLayoutConstraint(item: blurView,
                                   attribute: .centerX,
                                   relatedBy: .equal,
                                   toItem: coverView,
                                   attribute: .centerX,
                                   multiplier: 1.0,
                                   constant: 0),
                
                NSLayoutConstraint(item: blurView,
                                   attribute: .centerY,
                                   relatedBy: .equal,
                                   toItem: coverView,
                                   attribute: .centerY,
                                   multiplier: 1.0,
                                   constant: 0)
            ])
            
            parentView.addConstraints([
                NSLayoutConstraint(item: nsfwLabel,
                                   attribute: .centerX,
                                   relatedBy: .equal,
                                   toItem: parentView,
                                   attribute: .centerX,
                                   multiplier: 1.0,
                                   constant: 0),
                
                NSLayoutConstraint(item: nsfwLabel,
                                   attribute: .centerY,
                                   relatedBy: .equal,
                                   toItem: parentView,
                                   attribute: .centerY,
                                   multiplier: 1.0,
                                   constant: 0)
            ])
            
            nsfwCover = coverView
        }
    }
}
