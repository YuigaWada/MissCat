//
//  RxEureka.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/05/16.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Eureka
import RxCocoa
import RxSwift

extension RowOf: ReactiveCompatible {}

extension Reactive where Base: RowType, Base: BaseRow {
    var value: ControlProperty<Base.Cell.Value?> {
        let source = Observable<Base.Cell.Value?>.create { observer in
            self.base.onChange { row in
                observer.onNext(row.value)
//                row.updateCell()
            }
            return Disposables.create()
        }
        let bindingObserver = Binder(base) { row, value in
            row.value = value
        }
        return ControlProperty(values: source, valueSink: bindingObserver)
    }
}
