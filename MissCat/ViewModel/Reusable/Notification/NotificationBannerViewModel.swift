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
    convenience init?(with contents: NotificationModel, and disposeBag: DisposeBag) {
        let model: NotificationBannerModel = .init(from: nil, owner: nil)
        guard let item = model.getModel(notification: contents) else { return nil }
        
        let input = NotificationCellViewModel.Input(item: item)
        self.init(with: input, and: disposeBag)
    }
}
