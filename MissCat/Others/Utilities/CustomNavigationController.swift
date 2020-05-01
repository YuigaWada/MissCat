//
//  CustomNavigationController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/05/01.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import UIKit

class CustomNavigationController: UINavigationController {
    override var childForStatusBarStyle: UIViewController? { // ステータスバーの色をHomeViewController側からイジれるように
        return visibleViewController
    }
}
