//
//  Dictionary+MisskeyKit.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/03.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation

extension Dictionary {
    
    func toRawJson() -> String?  {
        do {
        let data = try JSONSerialization.data(withJSONObject: self)
        
        return String(data: data, encoding: .utf8)
        }
        catch {
            return nil
        }
    }
    
    func removeRedundant()-> Dictionary {
        guard let _self = self as? [String : Any] else { return self }
        
        return _self.filter{ // remove stuff like "" or nil
            if let stringValue = $0.value as? String {
                if stringValue == "" {
                    return false
                }
            }
            
            if let arrayValue = $0.value as? Array<Any> {
                return arrayValue.count != 0
            }
            
            switch $0.value {
            case Optional<Any>.none: //nil
                return false
            default:
                break
            }
            return true
            } as! Dictionary
    }
    
    func searchKey<T>(value targetValue: T)-> Any? where T : Equatable { // T: value's type
        
        let result = self.filter { key, value in
            if let value = value as? T {
                return value == targetValue
            }
            return false
        }
        return result
    }
    
  
}
