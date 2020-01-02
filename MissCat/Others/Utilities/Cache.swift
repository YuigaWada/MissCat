//
//  Cache.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/23.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit
import MisskeyKit
import Foundation
import YanagiText

public typealias Attachments = Dictionary<NSTextAttachment,YanagiText.Attachment>
public class Cache {
    
    //MARK: Singleton
    public static var shared: Cache = .init()
    
    //MARK: Var
    public var notes: [String: Cache.Note] = [:] // key: noteId
    public var users: [String: Cache.User] = [:] // key: username
    public var files: [Cache.File] = []
    
    private var me: UserModel?
    
    
    //MARK: Save
    public func saveNote(noteId: String, note: NSAttributedString, attachments: Attachments) {
        guard notes[noteId] == nil else { return }
        
        notes[noteId] = Note(treatedNote: note, attachments: attachments)
    }
    
    public func saveDisplayName(username: String, displayName: NSAttributedString, attachments: Attachments) {
        if let _ = users[username] {
            users[username]!.displayName = displayName
        }
        else {
            users[username] = User(iconImage: nil, displayName: displayName, attachments: attachments)
        }
    }
    
    public func saveIcon(username: String, image: UIImage) {
        if let _ = users[username] {
            users[username]!.iconImage = image
        }
        else {
            users[username] = User(iconImage: image, displayName: nil, attachments: [:])
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
        
        //Cache.Fileが存在しない場合はつくる
        guard !hasFile else { return }
        let file = File(noteId: noteId, images: [imageTuple])
        
        files.append(file)
    }
    
    
    
    //MARK: Get
    public func getNote(noteId: String)-> Cache.Note? {
        return notes[noteId]
    }
    
    public func getDisplayName(username: String)-> (displayName: NSAttributedString?, attachments: Attachments?){
        return  (displayName: users[username]?.displayName, attachments: users[username]?.attachments)
    }
    
    public func getIcon(username: String)-> UIImage? {
        return users[username]?.iconImage
    }
    
    public func getFiles(noteId: String)-> [(thumbnail: UIImage, originalUrl: String)]? {
        let options = files.filter {
            $0.noteId == noteId
        }
        
        guard options.count > 0 else { return nil }
        return options[0].images
    }
    
    public func getMe(result callback: @escaping (UserModel?)->()) {
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
    
}



public extension Cache{
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
        public var attachments: Dictionary<NSTextAttachment,YanagiText.Attachment> = [:]
    }
    
    struct User {
        public var iconImage: UIImage?
        public var displayName: NSAttributedString?
        public var attachments: Dictionary<NSTextAttachment,YanagiText.Attachment> = [:]
    }

    
    struct File {
        public var noteId: String
        public var images: [(thumbnail: UIImage, originalUrl: String)]
    }
}
