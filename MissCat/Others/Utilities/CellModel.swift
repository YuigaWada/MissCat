//
//  CellModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/06/30.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxCocoa
import RxDataSources
import RxSwift

// IdentifiableでEquatableなクラス
// RxDataSources等でIdentifiableType && Equatableを求められるモデルクラスはこれを継承する
class CellModel: IdentifiableType, Equatable {
    typealias Identity = String
    let identity: String = String(Float.random(in: 1 ..< 100))
    
    static func == (lhs: CellModel, rhs: CellModel) -> Bool {
        return lhs.identity == rhs.identity
    }
}
