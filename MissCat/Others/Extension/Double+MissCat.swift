//
//  Double+MissCat.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/17.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation


extension Double {
    func toAgo()-> String? {
        let endingDate = Date()
        let startingDate = endingDate.addingTimeInterval(-self)
        let calendar = Calendar.current
        
        let componentsNow = calendar.dateComponents([.month,.weekday, .day, .hour, .minute, .second], from: startingDate, to: endingDate)
        if let month = componentsNow.month, let weekday = componentsNow.weekday, let day = componentsNow.day, let hour = componentsNow.hour, let minute = componentsNow.minute, let seconds = componentsNow.second {
            if month >= 6 {
                return nil
            }
            else if month != 0 {
                return "\(month)m"
            }
            if weekday != 0 {
                return "\(weekday)w"
            }
            else if day != 0 {
                return "\(day)d"
            }
            else if hour != 0 {
                return "\(hour)h"
            }
            else if minute != 0 {
                return "\(minute)m"
            }
            else if seconds != 0 {
                return "\(seconds)s"
            }
            else { // if seconds == 0
                return "now"
            }
            
        }
        
        return nil
    }
}
