//
//  NotificationBannerModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/07/04.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import UIKit

class NotificationBannerModel: NotificationsModel {
    func getModel(with contents: NotificationCell.CustomModel) -> NotificationCell.Model {
        let id = UUID().uuidString
        return .init(notificationId: id, custom: contents)
    }
}
