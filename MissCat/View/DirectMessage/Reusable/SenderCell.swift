//
//  SenderCell.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/16.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxCocoa
import RxDataSources
import RxSwift
import UIKit

class SenderCell: UITableViewCell, ComponentType {
    typealias Transformed = SenderCell
    typealias Arg = SenderCell.Model
    
    @IBOutlet weak var iconImage: UIImageView!
    @IBOutlet weak var nameTextView: MisskeyTextView!
    @IBOutlet weak var messageTextView: MisskeyTextView!
    @IBOutlet weak var agoLabel: UILabel!
    
    private var isSkelton: Bool = false
    
    func transform(isSkelton: Bool = false) -> SenderCell {
        self.isSkelton = isSkelton
        return self
    }
    
    func transform(with arg: SenderCell.Arg) -> SenderCell {
        return self
    }
}

extension SenderCell {
    class Model: IdentifiableType, Equatable {
        typealias Identity = String
        let identity: String = String(Float.random(in: 1 ..< 100))
        
        let isSkelton: Bool
        
        let userId: String?
        let icon: String?
        let name: String?
        let username: String?
        let latestMessage: String?
        let createdAt: Date?
        
        var shapedName: MFMString?
        init(isSkelton: Bool, userId: String?, icon: String?, name: String?, username: String?, latestMessage: String?, shapedName: MFMString? = nil, createdAt: Date?) {
            self.isSkelton = isSkelton
            self.userId = userId
            self.icon = icon
            self.name = name
            self.username = username
            self.latestMessage = latestMessage
            self.shapedName = shapedName
            self.createdAt = createdAt
        }
        
        static func == (lhs: SenderCell.Model, rhs: SenderCell.Model) -> Bool {
            return lhs.identity == rhs.identity
        }
        
        static func fakeSkeltonCell() -> SenderCell.Model {
            return .init(isSkelton: true,
                         userId: nil,
                         icon: nil,
                         name: nil,
                         username: nil,
                         latestMessage: nil,
                         createdAt: nil)
        }
    }
    
    struct Section {
        var items: [Model]
    }
}

extension SenderCell.Section: AnimatableSectionModelType {
    typealias Item = SenderCell.Model
    typealias Identity = String
    
    var identity: String {
        return ""
    }
    
    init(original: SenderCell.Section, items: [SenderCell.Model]) {
        self = original
        self.items = items
    }
}
