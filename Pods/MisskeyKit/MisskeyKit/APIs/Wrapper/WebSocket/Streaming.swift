//
//  Streaming.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/05.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation
import Starscream


public typealias StreamingCallBack = (_ response: Any?, _ channel: SentStreamModel.Channel?, _ responseType: String?, MisskeyKitError?)->Void
extension MisskeyKit {
    public class Streaming {
        
        private var socket: WebSocket?
        private var ids: [String:SentStreamModel.Channel] = [:]
        
        public var isConnected: Bool = false
        
        public init() {}
        
        deinit {
            guard let socket = socket else {return}
            socket.disconnect(forceTimeout: 0)
            self.socket = nil
        }
        
        //MARK:- Connection
        public func connect(apiKey: String, channels: [SentStreamModel.Channel], response callback: @escaping StreamingCallBack)-> Bool {
            let wsUrlString = "wss://misskey.io/streaming?i=" + apiKey
            guard let wsUrl = URL(string: wsUrlString) else { return false }
            
            self.socket = WebSocket(url: wsUrl)
            setupConnection(channels: channels, callback: callback)
            
            self.socket!.connect()
            return true
        }
        
        
        
        // Private Methods
        private func setupConnection(channels: [SentStreamModel.Channel], callback: @escaping StreamingCallBack) {
            guard let socket = self.socket else { return }
            
            //socket.disableSSLCertValidation = true
            socket.onConnect = {
                self.isConnected = true
                
                socket.write(pong: Data())
                self.shakeHandsForChannnels(channels, callback: callback)
            }
            
            socket.onDisconnect = { (error: Error?) in
                self.isConnected = false
                callback(nil, nil, nil, .CannotConnectStream)
            }
            
            socket.onText = { (text: String) in
                let (response, channel, responseType) = self.handleEvent(rawJson: text)
                
                if response == nil {
                    callback(response, channel, responseType, .UnknownTypeResponse)
                    return
                }
                
                callback(response, channel, responseType, nil)
            }
            
            socket.onData = { (data: Data) in
                guard let text = String(data: data, encoding: .utf8) else {
                    callback(nil, nil, nil, .UnknownTypeResponse)
                    return }
                let (response, channel, responseType) = self.handleEvent(rawJson: text)
                callback(response, channel, responseType, nil)
            }
            
        }
        
        private func shakeHandsForChannnels(_ channels: [SentStreamModel.Channel], callback: StreamingCallBack) {
            guard channels.count > 0 else { return }
            
            channels.forEach{ channel in
                
                let uuid = NSUUID().uuidString.sha256()!
                let body = SentStreamModel.ChannelBody(channel: channel, id: uuid, params: [:])
                let sentTarget = SentStreamModel(type: "connect", body: body)
                
                ids[uuid] = channel //save uuid pairs.
                
                var jsonData: Data?
                do {
                    jsonData = try JSONEncoder().encode(sentTarget)
                } catch {
                    callback(nil, nil, nil, .FailedToDecodeJson)
                    return
                }
                
                let rawJson = String(data: jsonData!, encoding: .utf8)!
                
                self.socket!.write(string: rawJson)
            }
            
            callback(true, nil, "onConnect", nil)
        }
        
        
        //MARK:- Stop Listening
        public func stopListening(channels: [SentStreamModel.Channel]) throws {
            try channels.forEach{
                do { try self.stopListening(channel: $0) }
                catch { throw MisskeyKitError.NoStreamConnection }
            }
        }
        
        public func stopListening(channel: SentStreamModel.Channel) throws {
            guard let socket = socket else {
                throw MisskeyKitError.NoStreamConnection
            }
            
            let disconnectJson = "{\"type\":\"disconnect\",\"body\":{\"id\":\"\(String(describing: ids.searchKey(value: channel)))\"}}"
            socket.write(string: disconnectJson)
        }
        
        public func stopListening(noteIds: [String]) throws {
            try noteIds.forEach{
                do { try self.stopListening(noteId: $0) }
                catch { throw MisskeyKitError.NoStreamConnection }
            }
        }
        
        public func stopListening(noteId: String) throws {
            guard let socket = socket else {
                throw MisskeyKitError.NoStreamConnection
            }
            
            let disconnectJson = "{\"type\":\"unsubNote\",\"body\":{\"id\":\"\(noteId)\"}}"
            socket.write(string: disconnectJson)
        }
        
        
        //MARK:- Capturing
        
        public func captureNote(noteId: String) throws {
            guard let socket = socket else {
                throw MisskeyKitError.NoStreamConnection
            }
            
            let requestJson = "{\"type\":\"subNote\",\"body\":{\"id\":\"\(noteId)\"}}"
            socket.write(string: requestJson)
        }
        
        
        //MARK:- Handling Events
        
        // json = {type,body / id,type,body / UserModel, NoteModel}
        private func handleEvent(rawJson: String)-> (response: Any?, channel: SentStreamModel.Channel?, responseType: String?) {
            guard let (body, otherParams) = self.disassembleJson(rawJson), let type = otherParams["type"] as? String else {return (nil,nil,nil)}
            
            let isNoteUpdatedType: Bool = type == "noteUpdated"
            
            guard let typeInBody = body["type"] as? String else { return (nil,nil,nil) }
            
            if typeInBody == "readAllNotifications" {
                return ("readAllNotifications", SentStreamModel.Channel.main, "readAllNotifications")
            }
            
            guard let (bodyInBody, otherParamsInBody) = self.disassembleJson(body),
                let id = otherParamsInBody["id"] as? String,
                let BinBjson = bodyInBody.toRawJson() else { return (nil,nil,nil) }
            
            
            if isNoteUpdatedType {
                var response = BinBjson.decodeJSON(NoteUpdatedModel.self)
                
                guard response != nil, let updateType = NoteUpdatedModel.UpdateType(rawValue: typeInBody) else { return (nil,nil,nil) }
                
                
                response!.targetNoteId = id
                response!.type = updateType
                
                return (response: response, channel: .CapturedNoteUpdated , responseType: "CapturedNoteUpdated")
            }
            
            // ↓ The type of this json data is "channel". ↓
            
            var response: Any?
            if related2Notification(typeInBody) {
                // Convert a raw json to StreamingModel.
                response = MisskeyKit.arrayReactions(rawJson: BinBjson).decodeJSON(StreamingModel.self)
            }
            else if typeInBody == "followed" {
                // Convert a raw json to UserModel.
                response = BinBjson.decodeJSON(UserModel.self)
            }
            else {
                // Convert a raw json to NoteModel.
                response = MisskeyKit.arrayReactions(rawJson: BinBjson).decodeJSON(NoteModel.self)
            }
            
            return (response: response, channel: ids[id], responseType: typeInBody)
        }
        
        
        
        //MARK:- Utilities
        private func disassembleJson(_ rawJson: String)-> (body: [String:Any], others: [String:Any])? {
            do {
                let json = try JSONSerialization.jsonObject(with: rawJson.data(using: .utf8)!) as! [String:Any]
                return self.disassembleJson(json)
            }
            catch { return nil }
        }
        
        private func disassembleJson(_ json: [String:Any])-> (body: [String:Any], others: [String:Any])? {
            guard let bodyJson = json["body"] as? [String:Any] else { return nil }
            
            return (body: bodyJson, others: json)
        }
        
        private func related2Notification(_ target: String)-> Bool {
            let notifNameList = ["notification", "unreadNotification", "readAllNotifications"]
            return notifNameList.contains(target)
        }
        
        
    }
}

