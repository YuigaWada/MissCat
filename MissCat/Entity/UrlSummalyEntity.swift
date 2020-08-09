//
//  UrlSummalyEntity.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/08/01.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Foundation

class UrlSummalyEntity: Codable {
    init(title: String?, icon: String?, description: String?, thumbnail: String?, sitename: String?, sensitive: Bool?, url: String?) {
        self.title = title
        self.icon = icon
        self.description = description
        self.thumbnail = thumbnail
        self.sitename = sitename
        self.sensitive = sensitive
        self.url = url
    }
    
    let title: String?
    let icon: String?
    let description: String?
    let thumbnail: String?
    let sitename: String?
    let sensitive: Bool?
    let url: String?
}
