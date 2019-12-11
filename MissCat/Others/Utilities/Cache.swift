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

public class Cache {
    
    //MARK: Singleton
    public static var shared: Cache = .init()
    
    //MARK: Var
    public var notes: [Cache.Note] = []
    public var icon: [Cache.Icon] = []
    public var files: [Cache.File] = []
    
    private var me: UserModel?
    
    
    //MARK: Save
    public func saveNote(noteId: String, note: NSAttributedString) {
        notes.append(Note(noteId: noteId, treatedNote: note))
    }
    
    public func saveIcon(username: String, image: UIImage) {
        icon.append(Icon(username: username, image: image))
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
    public func getNote(noteId: String)-> NSAttributedString? {
        let options = notes.filter {
            $0.noteId == noteId
        }
        
        guard options.count > 0 else { return nil }
        return options[0].treatedNote
    }
    
    public func getIcon(username: String)-> UIImage? {
        let options = icon.filter {
            $0.username == username
        }
        
        guard options.count > 0 else { return nil }
        return options[0].image
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
        public var noteId: String
        public var treatedNote: NSAttributedString
    }
    
    struct Icon {
        public var username: String
        public var image: UIImage
    }
    
    struct File {
        public var noteId: String
        public var images: [(thumbnail: UIImage, originalUrl: String)]
    }
}
