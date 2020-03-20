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
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        setupMissCat()
        setupCognito()
        setupNotifications(with: application)
        
        return true
    }
    
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // バックグラウンドで実行する処理
        print("Back")
        sendNotification()
//        completionHandler(.newData)
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let appState = application.applicationState
        
        switch appState {
        case .active:
            sendNotification()
        case .inactive:
            sendNotification()
        case .background:
            sendNotification()
        @unknown default:
            sendNotification()
        }
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
        _ = EmojiHandler.handler
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
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        })
    }
    
    private func sendNotification() {
        let content = UNMutableNotificationContent()
        content.title = "通知タイトル"
        content.body = "通知本文"
        content.sound = UNNotificationSound.default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "HogehogeNotification", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
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
