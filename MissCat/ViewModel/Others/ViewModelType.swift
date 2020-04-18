//
//  ViewModelType.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/12/13.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation

protocol ViewModelType {
    // Input: rx.tap等のイベントはtriggerとしてInputに打ち込むが、hogehoge.rx.textのようなBinderに対するbindingはView側で行う
    associatedtype Input
    associatedtype Output
    associatedtype State
    
//    func transform() -> Output
}
