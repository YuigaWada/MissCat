//
//  Error+MissCat.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/06.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit

extension Error {
    var description: String {
        let error = self as? MisskeyKitError
        return error?.description ?? localizedDescription
    }
}

extension MisskeyKitError {
    var description: String {
        switch self {
        case .ClientError:
            return "サーバー側の問題が発生しました"
        case .AuthenticationError:
            return "認証エラーが発生しました"
        case .ForbiddonError:
            return "ForbiddonError"
        case .ImAI:
            return "ImAI"
        case .TooManyError:
            return "TooManyError"
        case .InternalServerError:
            return "InternalServerError"
        case .CannotConnectStream:
            return "Streaming接続に失敗しました"
        case .NoStreamConnection:
            return "NoStreamConnection"
        case .FailedToDecodeJson:
            return "データ処理に失敗しました"
        case .FailedToCommunicateWithServer:
            return "サーバーとの通信に失敗しました"
        case .UnknownTypeResponse:
            return "UnknownTypeResponse"
        case .ResponseIsNull:
            return "ResponseIsNull"
        }
    }
}
