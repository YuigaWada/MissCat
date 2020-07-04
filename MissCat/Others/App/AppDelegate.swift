//
//  AppDelegate.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/07.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import CoreData
import FirebaseCore
import FirebaseInstanceID
import FirebaseMessaging
import MisskeyKit
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    // MARK: Main
    
    var window: UIWindow?
    private let gcmMessageIDKey = "gcm.message_id"
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
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
        if let messageID = userInfo[gcmMessageIDKey] {
            print("Message ID: \(messageID)")
        }
        
        print(userInfo)
    }
    
    // foreground時に通知が飛んできたらこれがよばれる
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if let contents = extractPayload(from: userInfo) {
            showNotificationBanner(with: contents) // アプリ内通知を表示
        }
        
        print(userInfo)
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
    
    /// バナー通知を表示する
    /// - Parameter raw: userInfo
    private func showNotificationBanner(with contents: NotificationData) {
        guard let children = window?.rootViewController?.children,
            children.count > 0,
            let homeVC = children[0] as? HomeViewController,
            let owner = Cache.UserDefaults.shared.getUser(userId: contents.ownerId) // どのユーザー宛の通知か
        else { return }
        
        let misskey = MisskeyKit(from: owner)
        misskey?.notifications.get(markAsRead: false) { notifications, _ in
            guard let notifications = notifications else { return }
            
            notifications.forEach {
                guard $0.id == contents.notificationId else { return }
                homeVC.showNotificationBanner(with: $0)
            }
        }
    }
    
    /// ペイロードからメッセージ等を抽出する
    /// - Parameter payload: [String:String]
    private func extractPayload(from payload: [AnyHashable: Any]) -> NotificationData? {
        guard let notificationId = payload["notification_id"] as? String,
            let ownerId = payload["owner_id"] as? String else { return nil }
        
        return NotificationData(ownerId: ownerId, notificationId: notificationId)
    }
    
    // MARK: UISceneSession Lifecycle
    
    @available(iOS 13.0, *)
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
    
    @available(iOS 13.0, *)
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
}
