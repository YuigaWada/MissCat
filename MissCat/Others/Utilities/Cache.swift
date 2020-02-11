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
    
    public var notes: [String: Cache.Note] = [:] // key: noteId
    
    // MEMO: YanagiTextと一対一にキャッシュする
    public var users: [String: Cache.User] = [:] // key: username
    public var files: [Cache.File] = []
    public var dataOnUrl: [String: Data] = [:] // key: url
    
    private var me: UserModel?
    
    // MARK: Save
    
    public func saveNote(noteId: String, note: NSAttributedString, attachments: Attachments) {
        guard notes[noteId] == nil else { return }
        
        notes[noteId] = Note(treatedNote: note, attachments: attachments)
    }
    
    public func saveDisplayName(username: String, displayName: NSAttributedString, attachments: Attachments, on yanagiText: YanagiText) {
        if let _ = users[username] {
            users[username]!.displayName = displayName
            users[username]!.yanagiTexts.append(yanagiText)
        } else {
            users[username] = User(iconImage: nil, displayName: displayName, yanagiTexts: [yanagiText], attachments: attachments)
        }
    }
    
    public func saveIcon(username: String, image: UIImage) {
        if let _ = users[username] {
            users[username]!.iconImage = image
        } else {
            users[username] = User(iconImage: image, displayName: nil, yanagiTexts: [], attachments: [:])
        }
    }
    
    public func saveFiles(noteId: String, image: UIImage, originalUrl: String) {
        let imageTuple = (thumbnail: image, originalUrl: originalUrl)
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
    
    public func saveUrlData(_ data: Data, on rawUrl: String) {
        dataOnUrl[rawUrl] = data
    }
    
    // MARK: Get
    
    public func getNote(noteId: String) -> Cache.Note? {
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
    
    public func getFiles(noteId: String) -> [(thumbnail: UIImage, originalUrl: String)]? {
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
        return dataOnUrl[rawUrl]
    }
}

public extension Cache {
    class UserDefaults {
        public static var shared: Cache.UserDefaults = .init()
        private let latestNotificationKey = "latest-notification"
        
        public func getLatestNotificationId(_ id: String) {
            Foundation.UserDefaults.standard.string(forKey: latestNotificationKey)
        }
        
        public func setLatestNotificationId(_ id: String) {
            Foundation.UserDefaults.standard.set(id, forKey: latestNotificationKey)
        }
    }
}

public extension Cache {
    struct Note {
        public var treatedNote: NSAttributedString
        public var attachments: [NSTextAttachment: YanagiText.Attachment] = [:]
    }
    
    struct User {
        public var iconImage: UIImage?
        public var displayName: NSAttributedString?
        
        public var yanagiTexts: [YanagiText]
        public var attachments: [NSTextAttachment: YanagiText.Attachment] = [:]
    }
    
    struct File {
        public var noteId: String
        public var images: [(thumbnail: UIImage, originalUrl: String)]
    }
}
