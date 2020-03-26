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
public class MissCatTableView: UITableView {
    public var _lockScroll: Bool = true
    public var lockScroll: PublishRelay<Bool>? {
        didSet {
            lockScroll?.subscribe(onNext: { self._lockScroll = $0 }).disposed(by: disposeBag)
        }
    }
    
    private var disposeBag = DisposeBag()
    private var onTop: Bool {
        return contentOffset.y <= 0
    }
    
    public override func performBatchUpdates(_ updates: (() -> Void)?, completion: ((Bool) -> Void)? = nil) {
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
}
