//
//  MisskeyKitError.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/23.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation

public enum MisskeyKitError: Error {
    
    //MARK: NATIVE
    
    //400
    case ClientError
    
    //401
    case AuthenticationError
    
    //403
    case ForbiddonError
    
    //418
    case ImAI
    
    //429
    case TooManyError
    
    //500
    case InternalServerError
    
    
    
    //MARK: ORIGINAL
    
    case CannotConnectStream
    
    case NoStreamConnection
    
    case FailedToDecodeJson
    
    case FailedToCommunicateWithServer
    
    case UnknownTypeResponse
    
    
    case ResponseIsNull
    
}
