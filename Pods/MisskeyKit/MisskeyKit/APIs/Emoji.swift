//
//  Emoji.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/09.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation

extension MisskeyKit {
    public class Emojis {
        
        private static var bundle = Bundle(for: MisskeyKit.self)
        private static var customEmojis: [EmojiModel]?
        private static var defaultEmoji: [DefaultEmojiModel]?
        
        public static func getDefault(completion: @escaping (([DefaultEmojiModel]?)->())) {
            
            if let defaultEmoji = defaultEmoji {
                completion(defaultEmoji)
                return
            }
            
            //If defaultEmoji was not set ...
            
            guard let path = bundle.path(forResource:"emojilist",
                                         ofType: "json")
                else { completion(nil); return }
            
            
            DispatchQueue.global(qos: .default).async {
                
                do {
                    let rawJson = try String(contentsOfFile: path, encoding: String.Encoding.utf8)
                    defaultEmoji = rawJson.decodeJSON([DefaultEmojiModel].self)
                } catch { completion(nil); return }
                
                completion(defaultEmoji)
            }
        }
        
        public static func getCustom(completion: @escaping (([EmojiModel]?)->())) {
            
            if let customEmojis = customEmojis {
                completion(customEmojis)
                return
            }
            
            MisskeyKit.meta.get{ result, error in
                guard let result = result, error == nil else { completion(nil); return }
                
                customEmojis = result.emojis
                completion(customEmojis)
            }
        }
        
        
        
    }
}


public struct DefaultEmojiModel: Codable {
    public let category: Category?
    public let char, name: String?
    public let keywords: [String]?
    
    public enum Category: String, Codable {
        case activity = "activity"
        case animalsAndNature = "animals_and_nature"
        case flags = "flags"
        case foodAndDrink = "food_and_drink"
        case objects = "objects"
        case people = "people"
        case symbols = "symbols"
        case travelAndPlaces = "travel_and_places"
    }
}

