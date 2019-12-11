//
//  ApiError.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/03.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//



public class ApiError: Codable {
    
    let error: Details?
    
    public class Details: Codable  {
        let message, code, id, kind: String?
    }
    
    static func checkNative(rawJson: String, _ statusCode: Int)-> MisskeyKitError {
        
        if let error = rawJson.decodeJSON(ApiError.self) {
            guard let details = error.error, let _ = details.message else {
                return MisskeyKitError.FailedToDecodeJson
            }
            
            return self.convertNativeError(code: statusCode)
        }
        
        return MisskeyKitError.FailedToDecodeJson
    }
    
    
    static func convertNativeError(code statusCode: Int)-> MisskeyKitError {
        switch statusCode {
        case 400:
            return .ClientError
            
        case 401:
            return .AuthenticationError
            
        case 403:
            return .ForbiddonError
            
        case 418:
            return .ImAI
            
        case 429:
            return .TooManyError
            
        case 500:
            return .InternalServerError
            
        default:
            return .UnknownTypeResponse
        }
    }
}
