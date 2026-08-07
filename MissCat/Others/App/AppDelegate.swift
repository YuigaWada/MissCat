//
//  AppDelegate.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/07.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import CoreData
import FirebaseCore
import FirebaseMessaging
import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    // MARK: Main
    
    var window: UIWindow?
    private var rootViewController: UIViewController? {
        if #available(iOS 13, *) {
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            return scene?.windows.first?.rootViewController
        } else {
            return window?.rootViewController
        }
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.

#if DEBUG
        // Visual/UI fixtures must not display system permission prompts, contact
        // Firebase, or hydrate real cached accounts. Ordinary launches continue
        // through the complete startup path below.
        if MissCatShellFixtureLaunch.isRequested || MissCatPersistenceProbeLaunch.isRequested {
            return true
        }

        if MissCatProfileOrdinaryRouteConfiguration.isEnabled {
            UIView.setAnimationsEnabled(false)
            setupMissCat()
            return true
        }

        if MissCatLoginProfileFixtureRoute.parse() != nil {
            setupMissCat()
            return true
        }

        // Automated tests must not trigger notification permission UI,
        // Firebase registration, or saved-account network side effects. The
        // ordinary application launch path below remains unchanged.
        if MissCatNoteOrdinaryRouteConfiguration.isEnabled
            || MissCatDiscoveryFixtureConfiguration.isAutomatedTestRun
            || MissCatDiscoveryOrdinaryRouteConfiguration.isEnabled {
            setupMissCat()
            return true
        }
#endif
        setupMissCat()
        setupFirebase()
        setupNotifications(with: application)
        setupUser()
        
        return true
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        UIApplication.shared.applicationIconBadgeNumber = 0 // アプリ開いたらバッジを削除する
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) {
        guard let envelope = MissCatPushEnvelope(payload: userInfo) else { return }
        routePush(envelope, opensRoute: false)
    }
    
    // foreground時に通知が飛んできたらこれがよばれる
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void)
    {
        if let envelope = MissCatPushEnvelope(payload: userInfo) {
            routePush(envelope, opensRoute: false)
        }
        completionHandler(UIBackgroundFetchResult.newData)
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {}
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print(error)
    }
    
    // MARK: Setup
    
    private func setupMissCat() {
        Theme.shared.set()
    }
    
    private func setupFirebase() {
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
    }
    
    private func setupNotifications(with application: UIApplication) {
        checkNotifyPermission(with: application)
        application.registerForRemoteNotifications()
    }
    
    private func setupUser() {
        let savedUsers = Cache.UserDefaults.shared.getUsers()
        
        savedUsers.forEach { user in
            self.registerSw(for: user)
            self.setupEmojiHandler(for: user)
        }
    }
    
    private func registerSw(for user: SecureUser) {
        #if targetEnvironment(simulator)
            let misscatApi = MisscatApi(apiKeyManager: MockApiKeyManager(), and: user)
            misscatApi.registerSw()
        #else
            let misscatApi = MisscatApi(apiKeyManager: ApiKeyManager(), and: user)
            misscatApi.registerSw()
        #endif
    }
    
    private func setupEmojiHandler(for user: SecureUser) {
        EmojiHandler.setHandler(owner: user)
    }
    
    // MARK: Notifications
    
    private func checkNotifyPermission(with application: UIApplication) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.badge, .sound, .alert], completionHandler: { granted, error in
            guard error == nil, granted else { return }
            print("通知許可")
        })
    }
    
    private func routePush(_ envelope: MissCatPushEnvelope, opensRoute: Bool) {
        let users = Cache.UserDefaults.shared.getUsers()
        let identities = users.map {
            MissCatPushAccountIdentity(
                accountIdentifier: $0.accountIdentifier,
                apiUserID: $0.userId,
                instance: $0.instance
            )
        }
        guard let resolved = MissCatPushOwnerResolver.resolve(envelope, accounts: identities),
              let owner = users.first(where: {
                  $0.accountIdentifier == resolved.ownerAccountIdentifier
              })
        else { return }
        guard let home = rootViewController?.descendant(of: HomeViewController.self) else { return }
        home.handlePush(resolved, owner: owner, opensRoute: opensRoute)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if let envelope = MissCatPushEnvelope(payload: notification.request.content.userInfo) {
            routePush(envelope, opensRoute: false)
        }
        completionHandler([])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let envelope = MissCatPushEnvelope(payload: response.notification.request.content.userInfo) {
            routePush(envelope, opensRoute: true)
        }
        completionHandler()
    }
}

private extension UIViewController {
    func descendant<T: UIViewController>(of type: T.Type) -> T? {
        if let match = self as? T {
            return match
        }

        for child in children {
            if let match = child.descendant(of: type) {
                return match
            }
        }

        if let presentedViewController,
           let match = presentedViewController.descendant(of: type)
        {
            return match
        }

        return nil
    }
}
