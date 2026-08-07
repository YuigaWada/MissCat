//
//  AppDelegate.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/07.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    private let lifecycle = MissCatApplicationLifecycleCoordinator.shared

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if lifecycle.applicationDidFinishLaunching() {
            lifecycle.remoteRegistrationRequested()
            application.registerForRemoteNotifications()
        }
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        lifecycle.applicationDidBecomeActive()
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) {
        lifecycle.receiveRemoteNotification(userInfo, opensRoute: false)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        lifecycle.receiveRemoteNotification(userInfo, opensRoute: false)
        completionHandler(.newData)
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        lifecycle.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        lifecycle.didFailToRegisterForRemoteNotifications(error: error)
    }
}
