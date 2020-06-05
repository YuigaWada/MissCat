//
//  MisscatApi.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/05/12.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import FirebaseInstanceID
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
    
    init(apiKeyManager: ApiKeyManagerProtocol, and user: SecureUser) {
        self.apiKeyManager = apiKeyManager
        self.misskey = MisskeyKit(from: user)
    }
    
    /// 適切なendpointを生成し、sw/registerを叩く
    func registerSw() {
        guard let currentUser = Cache.UserDefaults.shared.getCurrentUser(),
            let apiKey = currentUser.apiKey,
            !baseApiUrl.isEmpty,
            !apiKey.isEmpty,
            !currentUser.userId.isEmpty else { return }
        
        misskey?.auth.setAPIKey(apiKey)
        InstanceID.instanceID().instanceID { result, error in
            guard error == nil else { print("Error fetching remote instance ID: \(error!)"); return }
            if let token = result?.token {
                self.registerSw(userId: currentUser.userId, token: token)
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
