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
import YanagiText

public typealias Attachments = [NSTextAttachment: YanagiText.Attachment]
public class Cache {
    // MARK: Singleton
    
    public static var shared: Cache = .init()
    
    // MARK: Var
    
    // 下２つのcacheはYanagiTextと一対一に対応してキャッシュしてあげる
    
    private var notes: [String: Cache.NoteOnYanagi] = [:] // key: noteId
    private var users: [String: Cache.UserOnYanagi] = [:] // key: username
    
    private var files: [Cache.File] = []
    private var dataOnUrl: [String: Data] = [:] // key: url
    
    private var me: UserModel?
    
    private lazy var applicationSupportDir = CreateApplicationSupportDir()
    
    // MARK: Save
    
    public func saveNote(noteId: String, note: NSAttributedString, attachments: Attachments) {
        guard notes[noteId] == nil else { return }
        
        notes[noteId] = NoteOnYanagi(treatedNote: note, yanagiTexts: [], attachments: attachments)
    }
    
    public func saveDisplayName(username: String, displayName: NSAttributedString, attachments: Attachments, on yanagiText: YanagiText) {
        if let _ = users[username] {
            users[username]!.displayName = displayName
            users[username]!.yanagiTexts.append(yanagiText)
        } else {
            users[username] = UserOnYanagi(iconImage: nil, displayName: displayName, yanagiTexts: [yanagiText], attachments: attachments)
        }
    }
    
    public func saveIcon(username: String, image: UIImage) {
        if let _ = users[username] {
            users[username]!.iconImage = image
        } else {
            users[username] = UserOnYanagi(iconImage: image, displayName: nil, yanagiTexts: [], attachments: [:])
        }
    }
    
    public func saveFiles(noteId: String, image: UIImage, originalUrl: String, type: NoteCell.FileType, isSensitive: Bool) {
        let imageTuple = (thumbnail: image, originalUrl: originalUrl, type: type, isSensitive: isSensitive)
        var hasFile: Bool = false
        
        files = files.map {
            guard $0.noteId == noteId else { return $0 }
            hasFile = true
            
            var file = $0
            file.images.append(imageTuple)
            return file
        }
        
        // Cache.Fileが存在しない場合はつくる
        guard !hasFile else { return }
        let file = File(noteId: noteId, images: [imageTuple])
        
        files.append(file)
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
    
    public func getDisplayName(username: String, on yanagiText: YanagiText) -> (displayName: NSAttributedString?, attachments: Attachments?) {
        if let user = users[username], user.yanagiTexts.filter({ $0 === yanagiText }).count > 0 {
            return (displayName: users[username]?.displayName, attachments: users[username]?.attachments)
        } else {
            return (displayName: nil, attachments: nil)
        }
    }
    
    public func getIcon(username: String) -> UIImage? {
        return users[username]?.iconImage
    }
    
    public func getFiles(noteId: String) -> [(thumbnail: UIImage, originalUrl: String, type: NoteCell.FileType, isSensitive: Bool)]? {
        let options = files.filter {
            $0.noteId == noteId
        }
        
        guard options.count > 0 else { return nil }
        return options[0].images
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
        
        public func getLatestNotificationId() -> String? {
            return Foundation.UserDefaults.standard.string(forKey: latestNotificationKey)
        }
        
        public func setLatestNotificationId(_ id: String) {
            Foundation.UserDefaults.standard.set(id, forKey: latestNotificationKey)
        }
        
        public func getCurrentLoginedApiKey() -> String? {
            return Foundation.UserDefaults.standard.string(forKey: currentLoginedApiKey)
        }
        
        public func getCurrentLoginedApiKey(_ id: String) {
            Foundation.UserDefaults.standard.set(id, forKey: currentLoginedApiKey)
        }
    }
}

public extension Cache {
    struct NoteOnYanagi {
        public var treatedNote: NSAttributedString
        
        public var yanagiTexts: [YanagiText]
        public var attachments: [NSTextAttachment: YanagiText.Attachment] = [:]
    }
    
    struct UserOnYanagi {
        public var iconImage: UIImage?
        public var displayName: NSAttributedString?
        
        public var yanagiTexts: [YanagiText]
        public var attachments: [NSTextAttachment: YanagiText.Attachment] = [:]
    }
    
    struct File {
        public var noteId: String
        public var images: [(thumbnail: UIImage, originalUrl: String, type: NoteCell.FileType, isSensitive: Bool)]
    }
}
