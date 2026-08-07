//
//  Theme.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/17.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Foundation

struct ThemeModelStorage {
    let data: (_ key: String) -> Data?
    let setData: (_ data: Data?, _ key: String) -> Void

    static var standard: ThemeModelStorage {
        ThemeModelStorage(
            data: { UserDefaults.standard.data(forKey: $0) },
            setData: { data, key in
                if let data {
                    UserDefaults.standard.set(data, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        )
    }
}

// MARK: Theme

@MainActor
public final class Theme {
    static let shared = Theme()

    enum PersistenceError: Error {
        case writeOrReadbackFailed
        case rollbackFailed
    }

    var currentModel: Theme.Model?

    private let modelStorage: ThemeModelStorage
    private let persistencePublishObserver: ((Theme.Model) -> Void)?

    init(
        modelStorage: ThemeModelStorage = .standard,
        persistencePublishObserver: ((Theme.Model) -> Void)? = nil
    ) {
        self.modelStorage = modelStorage
        self.persistencePublishObserver = persistencePublishObserver
    }

    /// currentModelをsetします
    func set() {
        var candidate = Model.get(storage: modelStorage)
        if candidate == nil {
            guard let defaultModel = Model.getDefault() else { return }
            candidate = defaultModel
        }

        guard let candidate else { return }
        let normalized = candidate.copy()
        normalized.tab = checkTabs(normalized.tab) // 有効なフォーマットかチェックしておく
        guard let persisted = try? Model.saveChecked(with: normalized, storage: modelStorage) else { return }
        currentModel = persisted
    }
    
    func reset() {
        currentModel = nil
    }
    
    /// 有効なタブのみ取り出し、紐付けられたアカウント情報を詰めていく
    private func checkTabs(_ tabs: [Theme.Tab]?) -> [Theme.Tab] {
        guard let tabs = tabs else { return [] }

        let cache = Cache.UserDefaults.shared
        let users = cache.getUsers()
        let currentAccountIdentifier = cache.getCurrentUserId().flatMap { current in
            users.first(where: { $0.accountIdentifier == current })?.accountIdentifier
        } ?? users.first?.accountIdentifier

        let transformed: [Theme.Tab] = tabs.compactMap {
            guard let accountIdentifier = Self.resolvedTabOwnerIdentifier(
                $0.userId,
                users: users,
                fallbackAccountIdentifier: currentAccountIdentifier
            ) else { return nil }
            
            // userIdを持たないhomeタブ、またはデフォルト値のhomeタブは名前を@usernameに変更する
            if $0.kind == .home, $0.userId == nil || $0.name == "___Home___" {
                let username = users.first {
                    $0.accountIdentifier == accountIdentifier
                }?.username ?? ""
                return Theme.Tab(
                    name: "@\(username)",
                    kind: $0.kind,
                    userId: accountIdentifier,
                    listId: $0.listId
                )
            }
            
            return Theme.Tab(
                name: $0.name,
                kind: $0.kind,
                userId: accountIdentifier,
                listId: $0.listId
            )
        }
        
        // 有効なタブが存在しなかった場合
        if transformed.count == 0 {
            let defaultTabs = Theme.Model.getDefault()?.tab ?? [] // デフォルトのタブを代入しておく
            let hasAccounts = Cache.UserDefaults.shared.getUsers().count > 0
            return hasAccounts ? checkTabs(defaultTabs) : defaultTabs
        }
        
        return transformed
    }

    /// Theme archives historically stored a bare server user ID. Preserve exact
    /// instance-scoped IDs, migrate a bare ID only when it has one match, and route
    /// missing/ambiguous owners through the deterministic current-account fallback.
    nonisolated static func resolvedTabOwnerIdentifier(
        _ storedIdentifier: String?,
        users: [SecureUser],
        fallbackAccountIdentifier: String?
    ) -> String? {
        let fallback = fallbackAccountIdentifier.flatMap { identifier in
            users.first(where: { $0.accountIdentifier == identifier })?.accountIdentifier
        } ?? users.first?.accountIdentifier

        guard let storedIdentifier else { return fallback }
        if let exact = users.first(where: { $0.accountIdentifier == storedIdentifier }) {
            return exact.accountIdentifier
        }

        let legacyMatches = users.filter { $0.userId == storedIdentifier }
        guard legacyMatches.count == 1 else { return fallback }
        return legacyMatches[0].accountIdentifier
    }
    
    /// currentModelのタブ情報を全て削除する
    func removeAllTabs() {
        if currentModel == nil { set() }

        guard let currentModel else { return }
        let candidate = currentModel.copy()
        candidate.tab = Model.getDefault()?.tab ?? [] // デフォルトのタブに戻す
        _ = try? saveAtomically(with: candidate)
    }
    
    /// 削除しようとしているアカウントが紐付けられたタブを削除しておく
    /// - Parameter user: SecureUser
    func removeUserTabs(for user: SecureUser) -> Bool {
        if currentModel == nil { set() }
        
        if let currentModel {
            let hasAnotherLegacyMatch = Cache.UserDefaults.shared.getUsers().contains {
                $0.userId == user.userId && $0.accountIdentifier != user.accountIdentifier
            }
            let result = Self.removingTabs(
                forAccountIdentifier: user.accountIdentifier,
                legacyUserID: hasAnotherLegacyMatch ? nil : user.userId,
                from: currentModel.tab,
                defaults: Model.getDefault()?.tab ?? []
            )
            let candidate = currentModel.copy()
            candidate.tab = result.tabs

            guard (try? saveAtomically(with: candidate)) != nil else { return false }
            
            // Three account-bound tabs are replaced by the three defaults. Comparing
            // only the count reports that as unchanged and prevents the main shell
            // from rebuilding with the repaired configuration.
            return result.changed
        }
        
        return false
    }

    nonisolated static func removingTabs(
        for userID: String,
        from tabs: [Theme.Tab],
        defaults: [Theme.Tab]
    ) -> (tabs: [Theme.Tab], changed: Bool) {
        removingTabs(
            forAccountIdentifier: userID,
            legacyUserID: nil,
            from: tabs,
            defaults: defaults
        )
    }

    nonisolated static func removingTabs(
        forAccountIdentifier accountIdentifier: String,
        legacyUserID: String?,
        from tabs: [Theme.Tab],
        defaults: [Theme.Tab]
    ) -> (tabs: [Theme.Tab], changed: Bool) {
        let filtered = tabs.filter { tab in
            guard tab.userId != accountIdentifier else { return false }
            guard let legacyUserID else { return true }
            return tab.userId != legacyUserID
        }
        let repaired = filtered.isEmpty ? defaults : filtered
        return (repaired, repaired != tabs)
    }
    
    /// viewの再launchが必要か
    /// - Parameters:
    ///   - model1: 比較対象1
    ///   - model2: 比較対象2
    nonisolated static func needAllRelaunch(
        between model1: Theme.Model,
        and model2: Theme.Model
    ) -> Bool {
        if model1.isEqual(to: model2) {
            return false
        }
        
        let sameColorMode = model1.colorMode == model2.colorMode
        return !sameColorMode
    }
    
    /// Compatibility entry point for legacy callers that cannot surface persistence
    /// failures. New settings code must use `saveAtomically(with:)`.
    func save(with newModel: Theme.Model) {
        _ = try? saveAtomically(with: newModel)
    }

    /// Writes, reads back, and verifies the complete theme before publishing it.
    /// A failed write restores the exact previous bytes and leaves runtime state
    /// untouched. If restoration itself cannot be verified, a distinct error is
    /// returned so callers never mistake the candidate for committed state.
    @discardableResult
    func saveAtomically(with newModel: Theme.Model) throws -> Theme.Model {
        let oldPersistedData = modelStorage.data(Model.storageKey)
        let oldRuntimeModel = currentModel
        let normalized = newModel.copy()
        normalized.tab = checkTabs(normalized.tab)

        do {
            let persisted = try Model.saveChecked(with: normalized, storage: modelStorage)
            let changed = oldRuntimeModel.map { !$0.isEqual(to: persisted) } ?? true
            currentModel = persisted
            if changed {
                persistencePublishObserver?(persisted)
            }
            return persisted
        } catch {
            modelStorage.setData(oldPersistedData, Model.storageKey)
            guard modelStorage.data(Model.storageKey) == oldPersistedData else {
                currentModel = oldRuntimeModel
                throw PersistenceError.rollbackFailed
            }
            currentModel = oldRuntimeModel
            throw PersistenceError.writeOrReadbackFailed
        }
    }
}


// MARK: Theme Model

public extension Theme {
    internal enum ColerMode: String, Codable {
        case light
        case dark
    }
    
    enum TabKind: String, Codable {
        case home
        case local
        case global
        case social
        case user
        case list
    }
    
    struct Tab: Codable, Equatable {
        var name: String
        var kind: TabKind
        
        var userId: String?
        var listId: String?
    }
    
    class Model: Codable {
        var tab: [Tab]
        var mainColorHex: String
        var colorMode: ColerMode
        
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

        func copy() -> Model {
            Model(tab: tab, mainColorHex: mainColorHex, colorMode: colorMode)
        }
        
        // MARK: GET/SET
        
        static func get() -> Model? {
            get(storage: .standard)
        }

        static func get(storage: ThemeModelStorage) -> Model? {
            guard let data = storage.data(storageKey),
                  let model = decode(data) else { return nil }
            
            let cache = Cache.UserDefaults.shared
            let users = cache.getUsers()
            let currentAccountIdentifier = cache.getCurrentUserId().flatMap { current in
                users.first(where: { $0.accountIdentifier == current })?.accountIdentifier
            } ?? users.first?.accountIdentifier
            var migratedOwner = false

            model.tab = model.tab.map {
                let resolved = Theme.resolvedTabOwnerIdentifier(
                    $0.userId,
                    users: users,
                    fallbackAccountIdentifier: currentAccountIdentifier
                )
                migratedOwner = migratedOwner || resolved != $0.userId
                return .init(
                    name: $0.name,
                    kind: $0.kind,
                    userId: resolved,
                    listId: $0.listId
                )
            }
            
            if migratedOwner {
                _ = try? saveChecked(with: model, storage: storage)
            }
            
            return model
        }
        
        static func save(with target: Model) {
            _ = try? saveChecked(with: target, storage: .standard)
        }

        @discardableResult
        static func saveChecked(
            with target: Model,
            storage: ThemeModelStorage
        ) throws -> Model {
            let encoded = try JSONEncoder().encode(target)
            storage.setData(encoded, storageKey)
            guard let readback = storage.data(storageKey),
                  let decoded = decode(readback),
                  decoded.isEqual(to: target)
            else {
                throw Theme.PersistenceError.writeOrReadbackFailed
            }
            return decoded
        }

        static func decode(_ data: Data) -> Model? {
            try? JSONDecoder().decode(Model.self, from: data)
        }

        static let storageKey = "theme-key"
        
        static func getDefault() -> Model? {
            guard let data = defaultJson.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(Model.self, from: data)
        }
        
        private static let defaultJson = """
        {
            "tab": [
                {
                    "name": "___Home___",
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
