//
//  MisskeyKit.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/04.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation

open class MisskeyKit {
    
    //MARK:- Singleton
    static public let auth: Auth = MisskeyKit.Auth()
    static public var notes: MisskeyKit.Notes = MisskeyKit.Notes()
    static public var users: MisskeyKit.Users = MisskeyKit.Users()
    static public var groups: MisskeyKit.Groups = MisskeyKit.Groups()
    static public var lists: MisskeyKit.Lists = MisskeyKit.Lists()
    static public var search: MisskeyKit.Search = MisskeyKit.Search()
    static public var notifications: MisskeyKit.Notifications = MisskeyKit.Notifications()
    static public var meta: MisskeyKit.Meta = MisskeyKit.Meta()
    static public var drive: MisskeyKit.Drive = MisskeyKit.Drive()
    static public var app: MisskeyKit.App = MisskeyKit.App()

    
    
    public static func changeInstance(instance: String = "misskey.io") {
        Api.instance = instance
    }
    
    //MARK:- Internal Methods
    internal static func handleAPI<T>(needApiKey: Bool = false, api: String, params: [String: Any], data: Data? = nil, fileType: String? = nil, type: T.Type, missingCount: Int? = nil, callback: @escaping (T?, MisskeyKitError?)->Void) where T : Decodable  {
        let hasAttachment = data != nil
        
        if hasAttachment && fileType == nil { return } // If fileType being nil ...
        
        if let missingCount = missingCount, missingCount >= 4 { return callback(nil, .FailedToCommunicateWithServer) }
        
        var params = params
        if needApiKey {
            params["i"] = auth.getAPIKey()
        }
        
        let completion = { (response: HTTPURLResponse?, resultRawJson: String?, error: MisskeyKitError?) in
            self.handleResponse(response: response,
                                resultRawJson: resultRawJson,
                                error: error,
                                needApiKey: needApiKey,
                                api: api,
                                params: params,
                                data: data,
                                fileType: fileType,
                                type: T.self,
                                missingCount: missingCount,
                                callback: callback)
        }
        
        
        
        
        if !hasAttachment {
            guard let rawJson = params.toRawJson() else { callback(nil, .FailedToDecodeJson); return }
            Requestor.post(url: Api.fullUrl(api), rawJson: rawJson, completion: completion)
        }
        else {
            Requestor.post(url: Api.fullUrl(api), paramsDic: params, data: data, fileType: fileType, completion: completion)
        }
    }
    
    
    
    // ** 参考 **
    //reactionsのkeyは無数に存在するため、codableでのパースは難しい。
    //そこで、生のjsonを直接弄り、reactionsを配列型に変更する。
    //Ex: "reactions":{"like":2,"😪":2} → "reactions":[{name:"like",count:2},{name:"😪",count:2}]
    
    internal static func arrayReactions(rawJson: String)-> String {
        
        //reactionsを全て取り出す
        let reactionsList = rawJson.regexMatches(pattern: "(\"reactions\":\\{[^\\}]*\\})")
        guard reactionsList.count > 0 else { return rawJson }
        
        
        var replaceList: [String] = []
        reactionsList.forEach{ // {"like":2,"😪":2} → [{name:"like",count:2},{name:"😪",count:2}]
            let reactions = $0[0]
            let shapedReactions = reactions.replacingOccurrences(of: "\\{([^\\}]*)\\}", with: "[$1]", options: .regularExpression)
                .replacingOccurrences(of: "\"([^\"]+)\":([0-9]+)", with: "{\"name\":\"$1\",\"count\":\"$2\"}", options: .regularExpression)
            
            replaceList.append(shapedReactions)
        }
        
        var replacedRawJson = rawJson
        for i in 0...reactionsList.count-1 {
            replacedRawJson = replacedRawJson.replacingOccurrences(of: reactionsList[i][0], with: replaceList[i])
        }
        
        return replacedRawJson
    }
    
    
    
    
    //MARK: Private Methods
    private static func handleResponse<T>(response: HTTPURLResponse?, resultRawJson: String?, error: MisskeyKitError?, needApiKey: Bool = false, api: String, params: [String: Any], data: Data? = nil, fileType: String? = nil, type: T.Type, missingCount: Int? = nil, callback: @escaping (T?, MisskeyKitError?)->Void) where T : Decodable {
        guard let resultRawJson = resultRawJson else {
            if let missingCount = missingCount {
                self.handleAPI(needApiKey: needApiKey,
                               api: api,
                               params: params,
                               type: type,
                               missingCount: missingCount + 1,
                               callback: callback)
            }
            
            // If being initial error...
            self.handleAPI(needApiKey: needApiKey,
                           api: api,
                           params: params,
                           type: type,
                           missingCount: 1,
                           callback: callback)
            
            return
        }
        
        let resultJson = arrayReactions(rawJson: resultRawJson) // Changes a form of reactions to array.
        
        if let response = response, response.statusCode == 200, resultJson.count == 0  {
            callback(nil, nil)
            return
        }
        
        guard let json = resultJson.decodeJSON(type) else {
            if resultJson.count == 0 {
                guard String(reflecting: T.self) == "Swift.Bool" else {
                    callback(nil, .ResponseIsNull)
                    return
                }
                
                callback(nil, nil)
                return
            }
            
            //guard上のifでnilチェックできているので強制アンラップでOK
            let error = ApiError.checkNative(rawJson: resultJson, response!.statusCode)
            callback(nil, error)
            return
        }
        
        callback(json, nil)
    }
    
}

