//
//  Theme.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/17.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Foundation
import RxCocoa
import RxSwift

// MARK: Theme

public class Theme {
    static var shared: Theme = .init()
    
    var currentModel: Theme.Model?
    var theme: PublishRelay<Theme.Model> = .init()
    
    /// currentModelをsetします
    func set() {
        var currentModel = Model.get()
        if currentModel == nil {
            guard let defaultModel = Model.getDefault() else { return }
            Model.save(with: defaultModel) // 存在しない場合はデフォルトの設定を保存しておく
            currentModel = defaultModel
        }
        
        self.currentModel = currentModel
    }
    
    /// viewの再launchが必要か
    /// - Parameters:
    ///   - model1: 比較対象1
    ///   - model2: 比較対象2
    static func needAllRelaunch(between model1: Theme.Model, and model2: Theme.Model) -> Bool {
        if model1.isEqual(to: model2) {
            return false
        }
        
        let sameColorMode = model1.colorMode == model2.colorMode
        return !sameColorMode
    }
    
    /// 新しいモデルを保存します
    /// - Parameter newModel: Theme.Model
    func save(with newModel: Theme.Model) {
        // 同じならばsaveしない
        if let currentModel = currentModel, currentModel.isEqual(to: newModel) {
            return
        }
        
        Model.save(with: newModel)
        
        currentModel = newModel
        theme.accept(newModel)
    }
}

// MARK: Theme Color

protocol ColorPattern {
    var ui: UIColorPattern { get }
    var hex: HexColorPattern { get }
}

protocol UIColorPattern {
    var base: UIColor { get }
    var sub0: UIColor { get }
    var sub1: UIColor { get }
    var sub2: UIColor { get }
    var sub3: UIColor { get }
    
    var text: UIColor { get }
}

protocol HexColorPattern {
    var base: String { get }
    var sub0: String { get }
    var sub1: String { get }
    var sub2: String { get }
    var sub3: String { get }
    
    var text: String { get }
}

extension Theme {
    class Color {
        struct Light: ColorPattern {
            var ui: UIColorPattern = UI()
            var hex: HexColorPattern = Hex()
            
            struct UI: UIColorPattern {
                var base: UIColor = .white
                var sub0: UIColor = .darkGray // 濃
                var sub1: UIColor = UIColor(hex: "C6C6C6")
                var sub2: UIColor = .lightGray // 淡
                var sub3: UIColor = UIColor(hex: "f0f0f0")
                
                var text: UIColor = .black
            }
            
            struct Hex: HexColorPattern {
                var base: String = "ffffff"
                var sub0: String = "555555"
                var sub1: String = "C6C6C6"
                var sub2: String = "D3D3D3"
                var sub3: String = "f0f0f0"
                
                var text: String = "000000"
            }
        }
        
        struct Dark: ColorPattern {
            var ui: UIColorPattern = UI()
            var hex: HexColorPattern = Hex()
            
            struct UI: UIColorPattern {
                var base: UIColor = UIColor(hex: "1f1f1f")
                var sub0: UIColor = UIColor(hex: "c5c5c5") // 淡
                var sub1: UIColor = UIColor(hex: "adadad")
                var sub2: UIColor = UIColor(hex: "555555")
                var sub3: UIColor = UIColor(hex: "303030") // 濃 (Lightと逆なので注意)
                
                var text: UIColor = .white
            }
            
            struct Hex: HexColorPattern {
                var base: String = "#1f1f1f"
                var sub0: String = "c5c5c5"
                var sub1: String = "adadad"
                var sub2: String = "555555"
                var sub3: String = "303030"
                
                var text: String = "ffffff"
            }
        }
    }
}

// MARK: Theme Model

extension Theme {
    enum ColerMode: String, Codable {
        case light
        case dark
    }
    
    public enum TabKind: String, Codable {
        case home
        case local
        case global
        case user
        case list
    }
    
    public struct Tab: Codable, Equatable {
        var name: String
        var kind: TabKind
        
        var userId: String?
        var listId: String?
    }
    
    public class Model: Codable {
        var tab: [Tab]
        var mainColorHex: String
        var colorMode: ColerMode
        
        var colorPattern: ColorPattern {
            return colorMode == .light ? Theme.Color.Light() : Theme.Color.Dark()
        }
        
        init(tab: [Theme.Tab], mainColorHex: String, colorMode: Theme.ColerMode) {
            self.tab = tab
            self.mainColorHex = mainColorHex
            self.colorMode = colorMode
        }
        
        // MARK: Utilities
        
        func isEqual(to old: Model) -> Bool {
            let new = self
            
            guard new.mainColorHex == old.mainColorHex,
                new.colorMode == old.colorMode else { return false }
            
            return hasEqualTabs(to: old)
        }
        
        func hasEqualTabs(to old: Model) -> Bool {
            let new = self
            guard new.tab.count == old.tab.count else { return false }
            
            for i in 0 ..< new.tab.count {
                let newTab = new.tab[i]
                let oldTab = old.tab[i]
                
                let sameKind = newTab.kind == oldTab.kind
                let sameName = newTab.name == oldTab.name
                let sameListId = newTab.listId == oldTab.listId
                let sameUserId = newTab.userId == oldTab.userId
                if !(sameKind && sameName && sameListId && sameUserId) {
                    return false
                }
            }
            return true
        }
        
        // MARK: GET/SET
        
        static func get() -> Model? {
            let key = getKey()
            guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(Model.self, from: data)
        }
        
        static func save(with target: Model) {
            let key = getKey()
            let data = try? JSONEncoder().encode(target)
            UserDefaults.standard.set(data, forKey: key)
        }
        
        private static func getKey() -> String {
            return "theme-key"
        }
        
        static func getDefault() -> Model? {
            guard let data = defaultJson.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(Model.self, from: data)
        }
        
        private static var defaultJson = """
        {
            "tab": [
                {
                    "name": "Home",
                    "kind": "home"
                },
                {
                    "name": "Local",
                    "kind": "local"
                },
                {
                    "name": "Global",
                    "kind": "global"
                }
            ],
            "mainColorHex": "2F7CF6",
            "colorMode": "light"
        }
        """
    }
}

// class Theme {
//    static var shared: Theme = .init()
//    var theme: PublishRelay<ThemeColorModel> = .init()
//    private var _theme: ThemeColorModel?
//
//    private lazy var defaultTheme = """
//        {
//            "general": {
//                "main": "2F7CF6",
//                "background": "ffffff",
//                "border": "C6C6C6"
//            },
//            "post": {
//                "text": "000000",
//                "link": "2F7CF6",
//                "reaction": "C6C6C6",
//                "myReaction": "DF785F",
//                "textSize": 11
//            },
//            "reply": {
//                "background": "EFEFEF",
//                "text": "000000",
//                "indicator": "AAAAAA"
//            },
//            "renote": {
//                "user": "2ecc71",
//                "commentRNBorder": "2F7CF6"
//            },
//            "notifications": {
//                "reaction": "e74c3c",
//                "renote": "2ecc71",
//                "text": "000000"
//            }
//        }
//    """
//
//    // MARK: LifeCycle
//
//    init() {
//        guard let themeJson = Cache.UserDefaults.shared.getTheme(), let _theme = ThemeModel.decode(themeJson) else {
//            setDefaultTheme()
//            return
//        }
//
//        self._theme = _theme.colorModel
//    }
//
//    private func setDefaultTheme() {
//        guard let defaultThemeModel = ThemeModel.decode(defaultTheme) else { fatalError("Internal Error.") }
//        _theme = defaultThemeModel.colorModel
//
//        Cache.UserDefaults.shared.setTheme(defaultTheme)
//    }
//
//    // MARK: Publics
//
//    func getCurrentTheme() -> ThemeColorModel {
//        guard let _theme = _theme else { fatalError("Internal Error") }
//        return _theme
//    }
//
//    func changeTheme(_ newTheme: ThemeColorModel) {
//        _theme = newTheme
//
//        theme.accept(newTheme)
//    }
//
//    /// bindingが完了した後に呼びだす。現在のtheme情報をstreamに流す。
//    func complete() {
//        guard let _theme = _theme else { return }
//        theme.accept(_theme)
//    }
// }
//
// class ThemeColorModel {
//    internal init(general: ThemeColorModel.General,
//                  post: ThemeColorModel.Post,
//                  reply: ThemeColorModel.Reply,
//                  renote: ThemeColorModel.Renote,
//                  notifications: ThemeColorModel.Notifications) {
//        self.general = general
//        self.post = post
//        self.reply = reply
//        self.renote = renote
//        self.notifications = notifications
//    }
//
//    var general: General
//    var post: Post
//    var reply: Reply
//    var renote: Renote
//    var notifications: Notifications
//
//    class General {
//        internal init(main: UIColor, background: UIColor, border: UIColor) {
//            self.main = main
//            self.background = background
//            self.border = border
//        }
//
//        var main: UIColor
//        var background: UIColor
//        var border: UIColor
//    }
//
//    class Post {
//        internal init(text: UIColor, link: UIColor, reaction: UIColor, myReaction: UIColor) {
//            self.text = text
//            self.link = link
//            self.reaction = reaction
//            self.myReaction = myReaction
//        }
//
//        var text: UIColor
//        var link: UIColor
//        var reaction: UIColor
//        var myReaction: UIColor
//        var textSize: Float = 11.0
//    }
//
//    class Reply {
//        internal init(background: UIColor, text: UIColor, indicator: UIColor) {
//            self.background = background
//            self.text = text
//            self.indicator = indicator
//        }
//
//        var background: UIColor
//        var text: UIColor
//        var indicator: UIColor
//    }
//
//    class Renote {
//        internal init(user: UIColor, commentRNBorder: UIColor) {
//            self.user = user
//            self.commentRNBorder = commentRNBorder
//        }
//
//        var user: UIColor
//        var commentRNBorder: UIColor
//    }
//
//    class Notifications {
//        internal init(reaction: UIColor, renote: UIColor, text: UIColor) {
//            self.reaction = reaction
//            self.renote = renote
//            self.text = text
//        }
//
//        var reaction: UIColor
//        var renote: UIColor
//        var text: UIColor
//    }
// }
//
// class ThemeModel: Codable {
//    var general: General
//    var post: Post
//    var reply: Reply
//    var renote: Renote
//    var notifications: Notifications
//
//    class General: Codable {
//        var main: String = "2F7CF6"
//        var background: String = "ffffff"
//        var border: String = "C6C6C6"
//    }
//
//    class Post: Codable {
//        var text: String = "000000"
//        var link: String = "2F7CF6"
//        var reaction: String = "C6C6C6"
//        var myReaction: String = "DF785F"
//        var textSize: Float = 11.0
//    }
//
//    class Reply: Codable {
//        var background: String = "EFEFEF"
//        var text: String = "000000"
//        var indicator: String = "AAAAAA"
//    }
//
//    class Renote: Codable {
//        var user: String = "2ecc71"
//        var commentRNBorder: String = "2F7CF6"
//    }
//
//    class Notifications: Codable {
//        var reaction: String = "e74c3c"
//        var renote: String = "2ecc71"
//        var text: String = "000000"
//    }
//
//    static func decode(_ raw: String) -> ThemeModel? {
//        guard raw.count > 0 else { return nil }
//
//        do {
//            return try JSONDecoder().decode(ThemeModel.self, from: raw.data(using: .utf8)!)
//        } catch {
//            print(error)
//            return nil
//        }
//    }
// }
//
// extension ThemeModel {
//    func encode() -> String? {
//        do {
//            let data = try JSONEncoder().encode(self)
//            return String(data: data, encoding: .utf8)
//        } catch {
//            return nil
//        }
//    }
//
//    var colorModel: ThemeColorModel {
//        let general = ThemeColorModel.General(main: .init(hex: self.general.main),
//                                              background: .init(hex: self.general.background),
//                                              border: .init(hex: self.general.border))
//
//        let post = ThemeColorModel.Post(text: .init(hex: self.post.text),
//                                        link: .init(hex: self.post.link),
//                                        reaction: .init(hex: self.post.reaction),
//                                        myReaction: .init(hex: self.post.myReaction))
//
//        let reply = ThemeColorModel.Reply(background: .init(hex: self.reply.background),
//                                          text: .init(hex: self.reply.text),
//                                          indicator: .init(hex: self.reply.indicator))
//
//        let renote = ThemeColorModel.Renote(user: .init(hex: self.renote.user),
//                                            commentRNBorder: .init(hex: self.renote.commentRNBorder))
//
//        let notifications = ThemeColorModel.Notifications(reaction: .init(hex: self.notifications.reaction),
//                                                          renote: .init(hex: self.notifications.renote),
//                                                          text: .init(hex: self.notifications.text))
//
//        return ThemeColorModel(general: general,
//                               post: post,
//                               reply: reply,
//                               renote: renote,
//                               notifications: notifications)
//    }
// }
