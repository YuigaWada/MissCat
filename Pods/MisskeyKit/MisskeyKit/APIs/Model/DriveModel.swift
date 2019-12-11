//
//  DriveModel.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/24.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation

public struct DriveInfoModel: Codable {
    public let capacity, usage: Int?
}


public struct DriveFileModel: Codable {
    public let id, createdAt, name: String?
    public let type: TypeEnum?
    public let md5: String?
    public let size: Int?
    public let isSensitive: Bool?
    public let properties: Properties?
    public let url: String?
    public  let thumbnailURL: String?
    public let folderId, folder, user: String?
    
    public struct Properties: Codable {
        public let width, height: Int?
        public let avgColor: String?
    }
    
    public enum TypeEnum: String, Codable {
        case imageJPEG = "image/jpeg"
        case imagePNG = "image/png"
        case videoMp4 = "video/mp4"
    }
    
}

public class DriveFolderModel: Codable {
    public let id: String?
    public let createdAt: Date?
    public let name: String?
    public let foldersCount, filesCount: Int?
    public let parentId: String?
    public let parent: DriveFolderModel?
}

