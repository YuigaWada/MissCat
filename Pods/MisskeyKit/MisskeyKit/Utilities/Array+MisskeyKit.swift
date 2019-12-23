//
//  Array+MisskeyKit.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/04.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation

extension Array {
    
    func toRawJson() -> String?  {
        do {
        let data = try JSONSerialization.data(withJSONObject: self)
        
        return String(data: data, encoding: .utf8)
        }
        catch {
            return nil
        }
    }
    
}
