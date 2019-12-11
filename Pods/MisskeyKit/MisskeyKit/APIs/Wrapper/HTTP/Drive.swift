//
//  Drive.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/24.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation

extension MisskeyKit {
    public class Drive {
        
        //MARK: Get Details
        public func getDriveInfo(result callback: @escaping (DriveInfoModel?, MisskeyKitError?)->()) {
            
            var params = [:] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "drive", params: params, type: DriveInfoModel.self) { info, error in
                
                if let error = error  { callback(nil, error); return }
                guard let info = info else { callback(nil, error); return }
                
                callback(info,nil)
            }
        }
        
        //MARK: Get Files
        public func getFiles(limit: Int = 10, sinceId: String = "", untilId: String = "", folderId: String = "", type: String = "", result callback: @escaping ([DriveFileModel]?, MisskeyKitError?)->()) {
            
            var params = ["limit":limit,
                          "sinceId":sinceId,
                          "folderId":folderId,
                          "untilId":untilId,
                          "type":type] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "drive/files", params: params, type: [DriveFileModel].self) { info, error in
                
                if let error = error  { callback(nil, error); return }
                guard let info = info else { callback(nil, error); return }
                
                callback(info,nil)
            }
        }
        
        // drive/streamの場合はフォルダ関係なしにfetchしてくる...?
        public func getFilesWithStream(limit: Int = 10, sinceId: String = "", untilId: String = "", type: String = "", result callback: @escaping ([DriveFileModel]?, MisskeyKitError?)->()) {
            
            var params = ["limit":limit,
                          "sinceId":sinceId,
                          "untilId":untilId,
                          "type":type] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "drive/stream", params: params, type: [DriveFileModel].self) { info, error in
                
                if let error = error  { callback(nil, error); return }
                guard let info = info else { callback(nil, error); return }
                
                callback(info,nil)
            }
        }
        
        
        
        public func findFileByHash(md5: String = "", result callback: @escaping ([DriveFileModel]?, MisskeyKitError?)->()) {
            
            var params = ["md5":md5] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "drive/files/find-by-hash", params: params, type: [DriveFileModel].self) { info, error in
                
                if let error = error  { callback(nil, error); return }
                guard let info = info else { callback(nil, error); return }
                
                callback(info,nil)
            }
        }
        
        
        
        public func showFile(fileId: String = "", url: String = "", result callback: @escaping (DriveFileModel?, MisskeyKitError?)->()) {
            
            var params = ["fileId":fileId,
                          "url":url] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "drive/files/find", params: params, type: DriveFileModel.self) { info, error in
                
                if let error = error  { callback(nil, error); return }
                guard let info = info else { callback(nil, error); return }
                
                callback(info,nil)
            }
        }
        
        
        
        public func getAttachedNotes(fileId: String, result callback: @escaping NotesCallBack) {
            
            var params = ["fileId":fileId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "drive/files/attached-notes", params: params, type: [NoteModel].self) { info, error in
                
                if let error = error  { callback(nil, error); return }
                guard let info = info else { callback(nil, error); return }
                
                callback(info,nil)
            }
        }
        
        
        
        
        
        //MARK: Control Files
        public func createFile(fileData: Data, fileType: String, name: String, isSensitive: Bool = false, force: Bool = false, folderId: String = "", result callback: @escaping (DriveFileModel?, MisskeyKitError?)->()) {
            
            var params = ["name":name,
                          "isSensitive":isSensitive,
                          "folderId":folderId,
                          "force":force] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "drive/files/create", params: params, data: fileData, fileType: fileType, type: DriveFileModel.self) { info, error in
                
                if let error = error  { callback(nil, error); return }
                guard let info = info else { callback(nil, error); return }
                
                callback(info,nil)
            }
        }
        
        public func deleteFile(fileId: String, result callback: @escaping BooleanCallBack) {
            
            var params = ["fileId":fileId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "drive/files/delete", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        public func updateFile(fileId: String, folderId: String = "", name: String = "", isSensitive: Bool = false, result callback: @escaping BooleanCallBack) {
            
            var params = ["fileId":fileId,
                          "folderId":folderId,
                          "name":name,
                          "isSensitive":isSensitive] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "drive/files/update", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        public func uploadFileFromUrl(url: String, folderId: String = "", name: String = "", isSensitive: Bool = false, force: Bool = false, result callback: @escaping BooleanCallBack) {
            
            var params = ["url":url,
                          "folderId":folderId,
                          "isSensitive":isSensitive,
                          "force":force] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "drive/files/upload-from-url", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        //MARK: Get Folders
        public func getFolders(limit: Int = 10, sinceId: String = "", untilId: String = "", folderId: String = "", result callback: @escaping ([DriveFileModel]?, MisskeyKitError?)->()) {
            
            var params = ["limit":limit,
                          "sinceId":sinceId,
                          "folderId":folderId,
                          "untilId":untilId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "drive/folders", params: params, type: [DriveFileModel].self) { info, error in
                
                if let error = error  { callback(nil, error); return }
                guard let info = info else { callback(nil, error); return }
                
                callback(info,nil)
            }
        }
        
        
        public func findFolder(name: String = "", parentId: String = "", result callback: @escaping ([DriveFolderModel]?, MisskeyKitError?)->()) {
            
            var params = ["name":name,
                          "parentId":parentId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "drive/folders/find", params: params, type: [DriveFolderModel].self) { info, error in
                
                if let error = error  { callback(nil, error); return }
                guard let info = info else { callback(nil, error); return }
                
                callback(info,nil)
            }
        }
        
        public func showFolder(folderId: String, result callback: @escaping (DriveFolderModel?, MisskeyKitError?)->()) {
            
            var params = ["folderId":folderId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "drive/folders/show", params: params, type: DriveFolderModel.self) { info, error in
                
                if let error = error  { callback(nil, error); return }
                guard let info = info else { callback(nil, error); return }
                
                callback(info,nil)
            }
        }
        
        
        
        //MARK: Control Folder
        public func createFolder(name: String, parentId: String = "", result callback: @escaping (DriveFolderModel?, MisskeyKitError?)->()) {
            
            var params = ["name":name,
                          "parentId":parentId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "drive/folders/create", params: params, type: DriveFolderModel.self) { info, error in
                
                if let error = error  { callback(nil, error); return }
                guard let info = info else { callback(nil, error); return }
                
                callback(info,nil)
            }
        }
        
        public func deleteFolder(folderId: String, result callback: @escaping BooleanCallBack) {
            
            var params = ["folderId":folderId] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "drive/folders/delete", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        public func updateFolder(parentId: String = "", folderId: String = "", name: String = "", result callback: @escaping BooleanCallBack) {
            
            var params = ["parentId":parentId,
                          "folderId":folderId,
                          "name":name] as [String : Any]
            
            params = params.removeRedundant()
            MisskeyKit.handleAPI(needApiKey: true, api: "drive/folders/update", params: params, type: Bool.self) { _, error in
                callback(error == nil, error)
            }
        }
        
        
    }
    
}

