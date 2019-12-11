//
//  UIImage+MissCat.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/13.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit
import SVGKit

extension URL {
    func toUIImage(_ completion: @escaping (UIImage?)->()){
        var request = URLRequest(url: self)
        request.timeoutInterval = 10

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data else { return completion(nil) }
            
            if let uiImage = UIImage(data: data) {
                 completion(uiImage)
            }
            else { // Type: SVG
                guard let svgImage = SVGKImage(data: data) else { return }
                completion(svgImage.uiImage)
            }
        }
        
        task.resume()
    }
}
