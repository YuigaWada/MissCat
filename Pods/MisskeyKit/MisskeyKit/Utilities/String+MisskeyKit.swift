//
//  String+MisskeyKit.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/03.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation

internal extension String {
    func decodeJSON<T>(_ type: T.Type) -> T? where T : Decodable {
        guard self.count > 0 else { return nil}
        
        do {
            return try JSONDecoder().decode(type, from: self.data(using: .utf8)!)
        }
        catch {
            print(error) // READ THIS CAREFULLY!
            return nil
        }
    }
    
    func sha256()-> String? {
        guard let stringData = self.data(using: String.Encoding.utf8) else { return nil }
        
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        stringData.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(self.count), &digest)
        }
        return digest.makeIterator().map { String(format: "%02x", $0) }.joined()
    }
    
    
    func regexMatches(pattern: String) -> [[String]] {
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
         let nsString = self as NSString
         let results  = regex.matches(in: self, options: [], range: NSMakeRange(0, nsString.length))
         return results.map { result in
             (0..<result.numberOfRanges).map {
                 result.range(at: $0).location != NSNotFound
                     ? nsString.substring(with: result.range(at: $0))
                     : ""
             }
         }
    }
    
}
