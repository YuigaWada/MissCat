//
//  MissCatTableView.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/24.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxCocoa
import RxSwift
import UIKit

/// スクロール位置を固定するTableView
/// Qiitaに記事書いた→ https://qiita.com/yuwd/items/bc152a0c9c4ce7754003
class MissCatTableView: PlaceholderTableView {
    var _lockScroll: Bool = true
    var lockScroll: PublishRelay<Bool>? {
        didSet {
            lockScroll?.subscribe(onNext: { self._lockScroll = $0 }).disposed(by: disposeBag)
        }
    }
    
    private lazy var spinner = UIActivityIndicatorView(style: .gray)
    private var disposeBag = DisposeBag()
    private var onTop: Bool {
        return contentOffset.y <= 0
    }
    
    override init(frame: CGRect, style: UITableView.Style) {
        super.init(frame: frame, style: style)
        setupSpinner()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSpinner()
    }
    
    override func performBatchUpdates(_ updates: (() -> Void)?, completion: ((Bool) -> Void)? = nil) {
        #if !targetEnvironment(simulator)
            let bottomOffset = contentSize.height - contentOffset.y
            
            if !onTop, _lockScroll {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
            }
            super.performBatchUpdates(updates, completion: { finished in
                guard finished, !self.onTop, self._lockScroll else { completion?(finished); return }
                self.contentOffset = CGPoint(x: 0, y: self.contentSize.height - bottomOffset)
                completion?(finished)
                CATransaction.commit()
        })
        #else
            super.performBatchUpdates(updates, completion: completion)
        #endif
    }
    
    private func setupSpinner() {
        spinner.color = UIColor.darkGray
        spinner.hidesWhenStopped = true
        
        let parentView = UIView()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        parentView.frame = spinner.frame.insetBy(dx: 0, dy: -10)
        parentView.addSubview(spinner)
        tableFooterView = parentView
        
        spinner.startAnimating()
        
        parentView.addConstraints([
            NSLayoutConstraint(item: parentView,
                               attribute: .centerX,
                               relatedBy: .equal,
                               toItem: spinner,
                               attribute: .centerX,
                               multiplier: 1.0,
                               constant: 0),
            
            NSLayoutConstraint(item: parentView,
                               attribute: .centerY,
                               relatedBy: .equal,
                               toItem: spinner,
                               attribute: .centerY,
                               multiplier: 1.0,
                               constant: 0)
        ])
    }
}
