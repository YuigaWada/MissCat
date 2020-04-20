//
//  ComponentType.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/12.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import UIKit

protocol ComponentType {
    associatedtype Arg
    associatedtype Transformed
    
    func transform(with arg: Arg) -> Transformed
}
