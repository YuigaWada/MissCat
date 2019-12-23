//
//  ApiUrl.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/03.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation


internal class Api {
    
    internal static var instance: String = "misskey.io" {
        didSet(newInstance) {
            self.instance = self.shapeUrl(newInstance)
        }
    }
    
    internal static func fullUrl(_ api: String)-> String {
        
        if api.prefix(1) == "/" {
            return "https://\(self.instance)/api" +  api
        }
        
        return "https://\(self.instance)/api/" +  api
    }
    
    private static func shapeUrl(_ url: String)-> String {
         return url.replacingOccurrences(of: "http(s|)://([^/]+).+",
                                         with: "$2",
                                         options: .regularExpression)
    }
    
}
