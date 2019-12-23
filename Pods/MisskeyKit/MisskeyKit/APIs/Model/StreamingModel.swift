//
//  StreamingModel.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/06.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation

public struct StreamingModel: Codable {
    public let id: String?
    public let reaction: String?
    public let createdAt: String?
    public let type: String?
    public let userId: String?
    public let user: UserModel?
    public let note: NoteModel?
}

public struct NoteUpdatedModel: Codable {
    public var type: UpdateType?
    public var targetNoteId: String?
    
    public let deletedAt: String?
    public let choice: Int?
    public let userId: String?
    public let reaction: String?

    
    public enum UpdateType: String, Codable {
        case reacted = "reacted"
        case pollVoted = "pollVoted"
        case deleted = "deleted"
    }
    
}



// ** for example **

// "body": {
//     "id": "7zqfs8k66y",
//     "createdAt": "2019-11-06T05:59:22.710Z",
//     "type": "reply",
//     "userId": "7zpjol10yf",
//     "user": {UserModel},
//     "note": {NoteModel}
// }
 
