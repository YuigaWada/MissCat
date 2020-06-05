//
//  MisskeyKit+MissCat.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/06/05.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit

extension MisskeyKit {
    convenience init(instance: String, apiKey: String) {
        self.init()
        self.changeInstance(instance: instance)
        self.auth.setAPIKey(apiKey)
    }
    
    convenience init?(from user: SecureUser) {
        guard let apiKey = user.apiKey else { return nil }
        self.init(instance: user.instance, apiKey: apiKey)
    }
    
    
    
}
