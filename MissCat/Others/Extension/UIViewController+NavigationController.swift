//
//  UIViewController+NavigationController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/09/06.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import UIKit

extension UIViewController: UIGestureRecognizerDelegate {
    // たまにnavigationControllerが機能しなくなってフリーズするため、フリーズしないように
    // 参考→　https://stackoverflow.com/a/36637556
    public func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        if navigationController.viewControllers.count > 1 {
            self.navigationController?.interactivePopGestureRecognizer?.delegate = self
            navigationController.interactivePopGestureRecognizer?.isEnabled = true
        } else {
            self.navigationController?.interactivePopGestureRecognizer?.delegate = nil
            navigationController.interactivePopGestureRecognizer?.isEnabled = false
        }
    }
}
