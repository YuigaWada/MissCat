//
//  Theme.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/17.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Foundation

public class Theme {
    public static var shared: Theme = .init()
    
    public lazy var defaultTheme = """
        {
            "general": {
                "main": "2F7CF6",
                "background": "ffffff",
                "border": "C6C6C6"
            },
            "post": {
                "text": "000000",
                "link": "2F7CF6",
                "reaction": "C6C6C6",
                "myReaction": "CF7058",
                "textSize": 11
            },
            "reply": {
                "background": "EFEFEF",
                "text": "000000"
            },
            "renote": {
                "user": "2ecc71",
                "commentRNBorder": "2F7CF6"
            },
            "notifications": {
                "reaction": "e74c3c",
                "renote": "2ecc71",
                "text": "000000"
            }
        }
    """
    
    private var model: ThemeModel?
    init() {
        guard let themeJson = Cache.UserDefaults.shared.getTheme(), let theme = ThemeModel.decode(themeJson) else {
            setDefaultTheme()
            return
        }
        
        model = theme
    }
    
    private func setDefaultTheme() {
        guard let defaultThemeModel = ThemeModel.decode(defaultTheme) else { fatalError("Internal Error.") }
        model = defaultThemeModel
        
        Cache.UserDefaults.shared.setTheme(defaultTheme)
    }
}

public class ThemeModel: Codable {
    public var general: General
    public var post: Post
    public var reply: Reply
    public var renote: Renote
    public var notifications: Notifications
    
    public class General: Codable {
        var main: String = "2F7CF6"
        var background: String = "ffffff"
        var border: String = "C6C6C6"
    }
    
    public class Post: Codable {
        var text: String = "000000"
        var link: String = "2F7CF6"
        var reaction: String = "C6C6C6"
        var myReaction: String = "CF7058"
        var textSize: Float = 11.0
    }
    
    public class Reply: Codable {
        var background: String = "EFEFEF"
        var text: String = "000000"
    }
    
    public class Renote: Codable {
        var user: String = "2ecc71"
        var commentRNBorder: String = "2F7CF6"
    }
    
    public class Notifications: Codable {
        var reaction: String = "e74c3c"
        var renote: String = "2ecc71"
        var text: String = "000000"
    }
    
    public static func decode(_ raw: String) -> ThemeModel? {
        guard raw.count > 0 else { return nil }
        
        do {
            return try JSONDecoder().decode(ThemeModel.self, from: raw.data(using: .utf8)!)
        } catch {
            print(error)
            return nil
        }
    }
}

public extension ThemeModel {
    func encode() -> String? {
        do {
            let data = try JSONEncoder().encode(self)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
