//
//  Cache.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/23.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation
import MisskeyKit
import SwiftLinkPreview
import UIKit

typealias Attachments = [NSTextAttachment: YanagiText.Attachment]
class Cache {
    // MARK: Singleton
    
    static var shared: Cache = .init()
    
    // MARK: Var
    
    private var icon: [String: UIImage] = [:] // key: username
    private var uiImage: [String: UIImage] = [:] // key: url
    private var dataOnUrl: [String: Data] = [:] // key: url
    private var urlPreview: [String: Response] = [:] // key: url
    
    private var me: UserModel?
    
    private lazy var applicationSupportDir = CreateApplicationSupportDir()
    
    // MARK: Reset
    
    func resetMyCache() {
        me = nil
    }
    
    // MARK: Save
    
    func saveIcon(username: String, image: UIImage) {
        icon[username] = image
    }
    
    func saveUiImage(_ image: UIImage, url: String) {
        uiImage[url] = image
    }
    
    func saveUrlData(_ data: Data, on rawUrl: String, toStorage: Bool = false) {
        dataOnUrl[rawUrl] = data
        if toStorage {
            saveToStorage(data: data, url: rawUrl)
        }
    }
    
    func saveUrlPreview(response: Response, on rawUrl: String) {
        urlPreview[rawUrl] = response
    }
    
    // MARK: Get
    
    func getIcon(username: String) -> UIImage? {
        return icon[username]
    }
    
    func getUiImage(url: String) -> UIImage? {
        return uiImage[url]
    }
    
    func getMe(result callback: @escaping (UserModel?) -> Void) {
        if let me = me {
            callback(me)
            return
        }
        
        MisskeyKit.users.i { user, error in
            guard let user = user, error == nil else { callback(nil); return }
            self.me = user
            
            callback(self.me)
        }
    }
    
    func getUrlData(on rawUrl: String) -> Data? {
        if !dataOnUrl.keys.contains(rawUrl), let savedOnStorage = getFromStorage(url: rawUrl) {
            saveUrlData(savedOnStorage, on: rawUrl) // RAM上に載せる
            return savedOnStorage
        }
        
        return dataOnUrl[rawUrl]
    }
    
    func getUrlPreview(on rawUrl: String) -> Response? {
        guard urlPreview.keys.contains(rawUrl) else { return nil }
        return urlPreview[rawUrl]
    }
    
    /// データをハッシュを利用して保存する
    /// - Parameters:
    ///   - data: Data
    ///   - url: Url
    private func saveToStorage(data: Data, url: String) {
        let filename = url.sha256() ?? url
        
        let path = applicationSupportDir.appendingPathComponent(filename)
        do {
            try data.write(to: path)
        } catch {
            /* Ignore */
            print(error)
        }
    }
    
    /// データをハッシュを利用して保存する
    /// - Parameter url: url
    private func getFromStorage(url: String) -> Data? {
        let filename = url.sha256() ?? url
        
        let path = applicationSupportDir.appendingPathComponent(filename)
        do {
            return try Data(contentsOf: path)
        } catch {
            return nil
        }
    }
    
    private func CreateApplicationSupportDir() -> URL {
        let manager = FileManager.default
        let applicationSupportDir = manager.urls(for: .applicationSupportDirectory,
                                                 in: .userDomainMask)[0]
        
        // デフォルトではsandbox内にApplication Supportが存在しないので、ディレクトリを作る必要がある
        if !manager.fileExists(atPath: applicationSupportDir.absoluteString) {
            do {
                try manager.createDirectory(at: applicationSupportDir,
                                            withIntermediateDirectories: false,
                                            attributes: nil)
            } catch {
                /* Ignore */
            }
        }
        
        return applicationSupportDir
    }
}

extension Cache {
    class UserDefaults {
        static var shared: Cache.UserDefaults = .init()
        private let latestNotificationKey = "latest-notification"
        private let currentLoginedApiKey = "current-logined-ApiKey"
        private let currentLoginedUserId = "current-logined-UserId"
        private let currentLoginedInstance = "current-logined-instance"
        private let currentVisibilityKey = "current-visibility"
        private let themeKey = "theme"
        
        func getLatestNotificationId() -> String? {
            return Foundation.UserDefaults.standard.string(forKey: latestNotificationKey)
        }
        
        func setLatestNotificationId(_ id: String) {
            Foundation.UserDefaults.standard.set(id, forKey: latestNotificationKey)
        }
        
        func getCurrentLoginedApiKey() -> String? {
            return Foundation.UserDefaults.standard.string(forKey: currentLoginedApiKey)
        }
        
        func setCurrentLoginedApiKey(_ id: String) {
            Foundation.UserDefaults.standard.set(id, forKey: currentLoginedApiKey)
        }
        
        func getCurrentLoginedUserId() -> String? {
            return Foundation.UserDefaults.standard.string(forKey: currentLoginedUserId)
        }
        
        func setCurrentLoginedUserId(_ id: String) {
            Foundation.UserDefaults.standard.set(id, forKey: currentLoginedUserId)
        }
        
        func getCurrentLoginedInstance() -> String? {
            return Foundation.UserDefaults.standard.string(forKey: currentLoginedInstance)
        }
        
        func setCurrentLoginedInstance(_ id: String) {
            Foundation.UserDefaults.standard.set(id, forKey: currentLoginedInstance)
        }
        
        func getCurrentVisibility() -> Visibility? {
            guard let raw = Foundation.UserDefaults.standard.string(forKey: currentVisibilityKey) else { return nil }
            return Visibility(rawValue: raw)
        }
        
        func setCurrentVisibility(_ visibility: Visibility) {
            Foundation.UserDefaults.standard.set(visibility.rawValue, forKey: currentVisibilityKey)
        }
        
//        func getTheme() -> String? {
//            return Foundation.UserDefaults.standard.string(forKey: themeKey)
//        }
//
//        func setTheme(_ rawJson: String) {
//            Foundation.UserDefaults.standard.set(rawJson, forKey: themeKey)
//        }
    }
}
