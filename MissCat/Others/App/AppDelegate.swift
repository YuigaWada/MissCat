//
//  AppDelegate.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/07.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import AWSCognito
import AWSSNS
import CoreData
import MisskeyKit
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    // MARK: Main
    
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        setupMissCat()
        // setupCognito()
        setupNotifications(with: application)
        
        return true
    }
    
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // バックグラウンドで実行する処理
//        notification()
        completionHandler(.newData)
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let appState = application.applicationState
        
//        switch appState {
//        case .active:
//            break
//        case .inactive:
//            notification()
//        case .background:
//            notification()
//        @unknown default:
//            notification()
//        }
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Device Tokenの取得
        let deviceTokenString = deviceToken.map { String(format: "%.2hhx", $0) }.joined()
        saveDeviceToken(deviceTokenString)
        
        let sns = AWSSNS.default()
        guard let request = AWSSNSCreatePlatformEndpointInput() else { return }
        
        request.token = deviceTokenString
        request.platformApplicationArn = "arn:aws:sns:ap-northeast-1:098581475404:app/APNS_SANDBOX/MissCat"
        request.customUserData = "{\"lang\":\"ja\"}" // 言語情報を渡す
        
        sns.createPlatformEndpoint(request).continueWith(executor: AWSExecutor.mainThread(), block: { task in
            guard task.error == nil,
                let result = task.result,
                let subscribeInput = AWSSNSSubscribeInput() else { return nil }
            
            subscribeInput.topicArn = "arn:aws:sns:ap-northeast-1:098581475404:app/APNS_SANDBOX/MissCat"
            subscribeInput.endpoint = result.endpointArn
            subscribeInput.protocols = "Application"
            sns.subscribe(subscribeInput)
            
            self.saveEndpointArn(result.endpointArn)
            return nil
        })
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print(error)
    }
    
    // MARK: Setup
    
    private func setupMissCat() {
        if let currentInstance = Cache.UserDefaults.shared.getCurrentLoginedInstance(),
            !currentInstance.isEmpty {
            MisskeyKit.changeInstance(instance: currentInstance)
            _ = EmojiHandler.handler
        }
        
        _ = Theme.shared
    }
    
    private func setupCognito() {
        // Amazon Cognito
        let credentialsProvider = AWSCognitoCredentialsProvider(regionType: .APNortheast1,
                                                                identityPoolId: "ap-northeast-1:70a071ae-23f9-46e8-b0f1-d5c9000e4f29")
        AWSServiceManager.default().defaultServiceConfiguration = AWSServiceConfiguration(region: .APNortheast1, credentialsProvider: credentialsProvider)
    }
    
    private func setupNotifications(with application: UIApplication) {
        application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
        checkNotifyPermission(with: application)
    }
    
    // MARK: Notifications
    
    private func checkNotifyPermission(with application: UIApplication) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.badge, .sound, .alert], completionHandler: { granted, error in
            guard error == nil, granted else { return }
            print("通知許可")
//            DispatchQueue.main.async {
//                application.registerForRemoteNotifications()
//            }
        })
    }
    
    private func notification() {
        // UserDefaultsに保存してから通知を流すように
        guard let current = Cache.UserDefaults.shared.getLatestNotificationId(),
            !current.isEmpty else { return }
        
        MisskeyKit.notifications.get(limit: 20, following: false) { results, error in
            guard let results = results, results.count > 0, error == nil else { return }
            
            if let notificationId = results[0].id { // 最新の通知をsave
                Cache.UserDefaults.shared.setLatestNotificationId(notificationId)
            }
            
            for index in 0 ..< results.count {
                let model = results[index]
                
                guard model.id != current else { break }
                self.sendNotification(of: model) // 順に通知を出していく
            }
        }
    }
    
    private func sendNotification(of model: NotificationModel) {
        guard let type = model.type else { return }
        
        var contents: NotificationContents?
        switch type {
        case .follow:
            contents = getFollowNotification(of: model)
        case .mention:
            contents = getReplyNotification(of: model)
        case .reply:
            contents = getReplyNotification(of: model)
        case .renote:
            contents = getRenoteNotification(of: model)
        case .quote:
            contents = getCommentRenoteNotification(of: model)
        case .reaction:
            contents = getReactionNotification(of: model)
        case .pollVote:
            break
        case .receiveFollowRequest:
            contents = getFollowNotification(of: model)
        default:
            return
        }
        
        if let contents = contents {
            sendNotification(title: contents.title, body: contents.body)
        }
    }
    
    private func getReplyNotification(of model: NotificationModel) -> NotificationContents? {
        guard let user = model.user, let note = model.note else { return nil }
        let name = getDisplayName(user)
        let text = note.text ?? ""
        
        let hasFile = (note.files?.count ?? 0) > 0
        let hasFileTitle = hasFile ? "画像を添付して" : ""
        
        return .init(title: "\(name)さんが\(hasFileTitle)返信しました",
                     body: text)
    }
    
    private func getFollowNotification(of model: NotificationModel) -> NotificationContents? {
        guard let user = model.user else { return nil }
        let name = getDisplayName(user)
        
        return .init(title: "",
                     body: "\(name)さんがフォローしました")
    }
    
    private func getRenoteNotification(of model: NotificationModel) -> NotificationContents? {
        guard let user = model.user, let note = model.note else { return nil }
        let name = getDisplayName(user)
        let text = note.text ?? ""
        
        return .init(title: "\(name)さんがRenoteしました",
                     body: text)
    }
    
    private func getCommentRenoteNotification(of model: NotificationModel) -> NotificationContents? {
        guard let user = model.user, let note = model.note else { return nil }
        let name = getDisplayName(user)
        let text = note.text ?? ""
        
        let hasFile = (note.files?.count ?? 0) > 0
        let hasFileTitle = hasFile ? "画像を添付して" : ""
        
        return .init(title: "\(name)さんが\(hasFileTitle)引用Renoteしました",
                     body: text)
    }
    
    private func getReactionNotification(of model: NotificationModel) -> NotificationContents? {
        guard let user = model.user, let note = model.note, let reaction = model.reaction else { return nil }
        let name = getDisplayName(user)
        let text = note.text ?? ""
        
        return .init(title: "\(name)さんがリアクション\"\(reaction)\"を送信しました",
                     body: text)
    }
    
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "misscat.\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
    
    private func getDisplayName(_ user: UserModel) -> String {
        guard let name = user.name else { return user.username ?? "" }
        return name.count > 13 ? String(name.prefix(13)) : name
    }
    
    // MARK: UserDefaults
    
    private func saveDeviceToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: "deviceToken")
    }
    
    private func saveEndpointArn(_ endpointArn: String?) {
        guard let endpointArn = endpointArn else { return }
        UserDefaults.standard.set(endpointArn, forKey: "endpointArn")
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

struct NotificationContents {
    let title: String
    let body: String
}
