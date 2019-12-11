//
//  Lists.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/05.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation

extension MisskeyKit {
    public class Lists {
        
        //MARK:- Controlling members
        public func pullUser(listId: String = "", userId: String = "", result callback: @escaping BooleanCallBack) {
            
            var params = ["listId":listId,
                          "userId":userId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "users/lists/pull", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        public func pushUser(listId: String = "", userId: String = "", result callback: @escaping BooleanCallBack) {
            
            var params = ["listId":listId,
                          "userId":userId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "users/lists/push", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        //MARK:- Controlling list itself
        public func create(name: String = "", result callback: @escaping ListCallBack) {
            var params = ["name":name] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "users/lists/create", params: params, type: ListModel.self) { list, error in
                if let error = error  { callback(nil, error); return }
                guard let list = list else { callback(nil, error); return }
                
                callback(list,nil)
            }
        }
        
        public func delete(listId: String = "", result callback: @escaping BooleanCallBack) {
            var params = ["listId":listId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "users/lists/delete", params: params, type: Bool.self) { list, error in
                callback(error == nil, error)
            }
        }
        
        //MARK:- Getting list information
        public func show(listId: String = "", result callback: @escaping ListCallBack) {
            
            var params = ["listId":listId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "users/lists/show", params: params, type: ListModel.self) { list, error in
                if let error = error  { callback(nil, error); return }
                guard let list = list else { callback(nil, error); return }
                
                callback(list,nil)
            }
        }
        
        public func getMyLists(listId: String = "", result callback: @escaping ListsCallBack) {
            
            var params = [:] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "users/lists/list", params: params, type: [ListModel].self) { list, error in
                if let error = error  { callback(nil, error); return }
                guard let list = list else { callback(nil, error); return }
                
                callback(list,nil)
            }
        }
        
        public func changeListName(listId: String = "", name: String = "", result callback: @escaping BooleanCallBack) {
            self.update(listId: listId, name: name, result: callback)
        }
        
        public func update(listId: String = "", name: String = "", result callback: @escaping BooleanCallBack) {
            
            var params = ["listId":listId,
                          "name":name] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "users/lists/update", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        
    }
}
