//
//  NotificationBannerViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/07/04.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxSwift

class NotificationBannerViewModel: NotificationCellViewModel {
    convenience init?(with contents: NotificationModel, and disposeBag: DisposeBag, owner: SecureUser) {
        let model: NotificationBannerModel = .init(from: nil, owner: nil)
        guard let item = model.getModel(notification: contents) else { return nil }
        
        // ownerを詰める
        item.owner = owner
        
        // Shapeしておく
        if item.type == .mention || item.type == .reply || item.type == .quote, let replyNote = item.replyNote {
            MFMEngine.shapeModel(replyNote)
        } else {
            MFMEngine.shapeModel(item)
        }
        
        let input = NotificationCellViewModel.Input(item: item)
        self.init(with: input, and: disposeBag)
    }
    
    convenience init?(with contents: NotificationCell.CustomModel, disposeBag: DisposeBag) {
        let model: NotificationBannerModel = .init(from: nil, owner: nil)
        let item = model.getModel(with: contents)
        
        let input = NotificationCellViewModel.Input(item: item)
        self.init(with: input, and: disposeBag)
    }
}
