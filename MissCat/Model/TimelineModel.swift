//
//  HomeModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/13.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit

//MARK: ENUM
public enum TimelineType {
    case Home
    case Local
    case Global
    
    case UserList
    case OneUser
    
    var needsStreaming: Bool {
        return self != .UserList && self != .OneUser
    }
    
    func convert2Channel()-> SentStreamModel.Channel? { //TimelineTypeをMisskeyKit.SentStreamModel.Channelに変換する
        switch self {
        case .Home: return .homeTimeline
        case .Local: return .localTimeline
        case .Global: return .globalTimeline
        default: return nil
        }
    }
}
class TimelineModel {
        
    
    public func getCellsModel(_ post: NoteModel)-> [NoteCell.Model]? {
        var cellsModel: [NoteCell.Model] = []
        
        if let reply = post.reply { // リプライ対象も表示する
            var replyCellModel = reply.getNoteCellModel()
            
            if replyCellModel != nil {
                replyCellModel!.isReplyTarget = true
                cellsModel.append(replyCellModel!)
            }
        }
        
        if let cellModel = post.getNoteCellModel() {
            cellsModel.append(cellModel)
        }
        
        return cellsModel.count > 0 ? cellsModel : nil
    }
    
   
    
    
    
}
