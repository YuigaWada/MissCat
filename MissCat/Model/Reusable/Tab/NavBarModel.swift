//
//  NavBarModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/06/10.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit

class NavBarModel {
    func getIconImage(from misskey: MisskeyKit, completion: @escaping (UIImage) -> Void) {
        misskey.users.i { userInfo, _ in
            _ = userInfo?.avatarUrl?.toUIImage {
                guard let image = $0 else { return }
                completion(image)
            }
        }
    }
}
