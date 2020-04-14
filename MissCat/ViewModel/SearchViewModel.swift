//
//  SearchViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/11.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxSwift

class SearchViewModel: ViewModelType {
    struct Input {}
    struct Output {}
    struct State {}
    
    private let input: Input
    private let disposeBag: DisposeBag
    
    init(with input: Input, and disposeBag: DisposeBag) {
        self.input = input
        self.disposeBag = disposeBag
    }
}
