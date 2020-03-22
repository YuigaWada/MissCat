//
//  Cache.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/23.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation
import MisskeyKit
import UIKit

public typealias Attachments = [NSTextAttachment: YanagiText.Attachment]
public class Cache {
    // MARK: Singleton
    
    public static var shared: Cache = .init()
    
    // MARK: Var
    
    // 下２つのcacheはYanagiTextと一対一に対応してキャッシュしてあげる
    // (YanagiTextのロジック上、attributedStringとカスタム絵文字のViewは一対一で対応しているため)
    
    private var notes: [String: Cache.NoteOnYanagi] = [:] // key: noteId
    private var users: [String: Cache.UserOnYanagi] = [:] // key: username
    
    private var uiImage: [String: UIImage] = [:] // key: url
    private var dataOnUrl: [String: Data] = [:] // key: url
    
    private var me: UserModel?
    
    private lazy var applicationSupportDir = CreateApplicationSupportDir()
    
    // MARK: Save
    
    public func saveNote(noteId: String, mfmString: MFMString, attachments: Attachments) {
        guard notes[noteId] == nil else { return }
        
        notes[noteId] = NoteOnYanagi(mfmString: mfmString, yanagiTexts: [], attachments: attachments)
    }
    
    public func saveDisplayName(username: String, mfmString: MFMString, attachments: Attachments, on yanagiText: YanagiText) {
        if let _ = users[username] {
            users[username]!.mfmString = mfmString
            users[username]!.yanagiTexts.append(yanagiText)
        } else {
            users[username] = UserOnYanagi(iconImage: nil, mfmString: mfmString, yanagiTexts: [yanagiText], attachments: attachments)
        }
    }
    
    public func saveIcon(username: String, image: UIImage) {
        if let _ = users[username] {
            users[username]!.iconImage = image
        } else {
            users[username] = UserOnYanagi(iconImage: image, mfmString: nil, yanagiTexts: [], attachments: [:])
        }
    }
    
    public func saveUiImage(_ image: UIImage, url: String) {
        uiImage[url] = image
    }
    
    public func saveUrlData(_ data: Data, on rawUrl: String, toStorage: Bool = false) {
        dataOnUrl[rawUrl] = data
        if toStorage {
            saveToStorage(data: data, url: rawUrl)
        }
    }
    
    // MARK: Get
    
    public func getNote(noteId: String) -> Cache.NoteOnYanagi? {
        return notes[noteId]
    }
    
    public func getDisplayName(username: String, on yanagiText: YanagiText) -> Cache.UserOnYanagi? {
        //        guard  if let user = users[username] else { return }
        //        let option = user.yanagiTexts.filter({ $0 === yanagiText })
        //        if option.count > 0 {
        //            return option[0]
        //        } else {
        //            return (displayName: nil, attachments: nil)
        //        }
        
        return users[username]
    }
    
    public func getIcon(username: String) -> UIImage? {
        return users[username]?.iconImage
    }
    
    public func getUiImage(url: String) -> UIImage? {
        return uiImage[url]
    }
    
    public func getMe(result callback: @escaping (UserModel?) -> Void) {
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
    
    public func getUrlData(on rawUrl: String) -> Data? {
        if !dataOnUrl.keys.contains(rawUrl), let savedOnStorage = getFromStorage(url: rawUrl) {
            saveUrlData(savedOnStorage, on: rawUrl) // RAM上に載せる
            return savedOnStorage
        }
        
        return dataOnUrl[rawUrl]
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

public extension Cache {
    class UserDefaults {
        public static var shared: Cache.UserDefaults = .init()
        private let latestNotificationKey = "latest-notification"
        private let currentLoginedApiKey = "current-logined-ApiKey"
        private let currentLoginedUserId = "current-logined-UserId"
        private let currentLoginedInstance = "current-logined-instance"
        private let themeKey = "theme"
        
        public func getLatestNotificationId() -> String? {
            return Foundation.UserDefaults.standard.string(forKey: latestNotificationKey)
        }
        
        public func setLatestNotificationId(_ id: String) {
            Foundation.UserDefaults.standard.set(id, forKey: latestNotificationKey)
        }
        
        public func getCurrentLoginedApiKey() -> String? {
            return Foundation.UserDefaults.standard.string(forKey: currentLoginedApiKey)
        }
        
        public func setCurrentLoginedApiKey(_ id: String) {
            Foundation.UserDefaults.standard.set(id, forKey: currentLoginedApiKey)
        }
        
        public func getCurrentLoginedUserId() -> String? {
            return Foundation.UserDefaults.standard.string(forKey: currentLoginedUserId)
        }
        
        public func setCurrentLoginedUserId(_ id: String) {
            Foundation.UserDefaults.standard.set(id, forKey: currentLoginedUserId)
        }
        
        public func getCurrentLoginedInstance() -> String? {
            return Foundation.UserDefaults.standard.string(forKey: currentLoginedInstance)
        }
        
        public func setCurrentLoginedInstance(_ id: String) {
            Foundation.UserDefaults.standard.set(id, forKey: currentLoginedInstance)
        }
        
        public func getTheme() -> String? {
            return Foundation.UserDefaults.standard.string(forKey: themeKey)
        }
        
        public func setTheme(_ rawJson: String) {
            Foundation.UserDefaults.standard.set(rawJson, forKey: themeKey)
        }
    }
}

public extension Cache {
    struct NoteOnYanagi {
        public var mfmString: MFMString
        
        public var yanagiTexts: [YanagiText]
        public var attachments: [NSTextAttachment: YanagiText.Attachment] = [:]
    }
    
    struct UserOnYanagi {
        public var iconImage: UIImage?
        public var mfmString: MFMString?
        
        public var yanagiTexts: [YanagiText]
        public var attachments: [NSTextAttachment: YanagiText.Attachment] = [:]
    }
}
