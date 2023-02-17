//
//  MisscatApi.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/05/12.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import FirebaseMessaging
import MisskeyKit

protocol ApiKeyManagerProtocol {
    var baseUrl: String { get }
}

struct MockApiKeyManager: ApiKeyManagerProtocol {
    var baseUrl = ""
}

class MisscatApi {
    private let misskey: MisskeyKit?
    private let apiKeyManager: ApiKeyManagerProtocol
    private let authSecret = "Q8Zgu-WDvN5EDT_emFGovQ"
    private let publicKey = "BJNAJpIOIJnXVVgCTAd4geduXEsNKre0XVvz0j-E_z-8CbGI6VaRPsVI7r-hF88MijMBZApurU2HmSNQ4e-cTmA"
    private var baseApiUrl: String {
        return apiKeyManager.baseUrl
    }
    
    static var name2emojis: [String: EmojiModel] = [:]
    static var emojis: [EmojiModel] = []

    init(apiKeyManager: ApiKeyManagerProtocol, and user: SecureUser) {
        self.apiKeyManager = apiKeyManager
        misskey = MisskeyKit(from: user)
        fetchEmojis()
    }
    
    /// 適切なendpointを生成し、sw/registerを叩く
    func registerSw() {
        guard let currentUser = Cache.UserDefaults.shared.getCurrentUser(),
              let apiKey = currentUser.apiKey,
              !baseApiUrl.isEmpty,
              !apiKey.isEmpty,
              !currentUser.userId.isEmpty else { return }
        
        misskey?.auth.setAPIKey(apiKey)
        Messaging.messaging().token { token, error in
            guard error == nil else { print("Error fetching remote instance ID: \(error!)"); return }
            if let token = token {
                self.registerSw(userId: currentUser.userId, token: token)
            }
        }
    }
    
    private func fetchEmojis() {
        misskey?.notes.getEmojis { emojis, _ in
            MisscatApi.emojis = emojis ?? []
            MisscatApi.emojis.forEach { emoji in
                if let name = emoji.name {
                    MisscatApi.name2emojis[name] = emoji
                }
            }
        }
    }
    
    private func registerSw(userId: String, token: String) {
        let endpoint = generateEndpoint(with: userId, and: token)
        
        misskey?.serviceWorker.register(endpoint: endpoint, auth: authSecret, publicKey: publicKey, result: { state, error in
            guard error == nil, let state = state else { return }
            print(state)
        })
    }
    
    private func generateEndpoint(with userId: String, and token: String) -> String {
        let currentLang = Locale.current.languageCode?.description ?? "ja"
        let endpoint = "\(baseApiUrl)/api/v1/push/\(currentLang)/\(userId)/\(token)"
        
        return endpoint
    }
}

public extension EmojiModel {
    static func convert(from dict: [String: String]?) -> [EmojiModel]? {
        let emojis = dict?.compactMap { EmojiModel(id: "", aliases: [], name: $0.key, url: $0.value, uri: $0.value, category: "other-instance") } ?? []
        MisscatApi.emojis += emojis
        emojis.forEach { emoji in
            if let name = emoji.name {
                MisscatApi.name2emojis[name] = emoji
            }
        }
        return MisscatApi.emojis
    }
}
