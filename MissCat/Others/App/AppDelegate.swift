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
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.

#if DEBUG
        // Visual/UI fixtures must not display system permission prompts, contact
        // Firebase, or hydrate real cached accounts. Unit-test hosts also avoid
        // enqueueing a prompt that could leak into a later UI-test launch.
        // Ordinary launches continue through the complete startup path below.
        let isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if MissCatShellFixtureLaunch.isRequested
            || MissCatPersistenceProbeLaunch.isRequested
            || MissCatAccountsSettingsAcceptanceLaunch.isRequested
            || MissCatProductionRootE2ELaunch.isRequested
            || isRunningUnitTests
        {
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
            MissCatEmojiCatalog.prepare(for: user)
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
        guard let resolved = MissCatPushOwnerResolver.resolve(envelope, accounts: identities)
        else { return }
        let action: MissCatApplicationPush.Action = opensRoute
            ? .openNotification(notificationID: resolved.notificationID)
            : .refreshNotifications(notificationID: resolved.notificationID)
        let deliveryKind = opensRoute ? "open" : "refresh"
        let push = MissCatApplicationPush(
            id: "\(resolved.ownerAccountIdentifier):\(resolved.notificationID):\(deliveryKind)",
            accountID: MissCatApplicationAccountID(
                rawValue: resolved.ownerAccountIdentifier
            ),
            action: action
        )
        Task {
            await MissCatApplicationPushIngress.shared.receive(push)
        }
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
