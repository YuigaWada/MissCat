//
//  UIImage+MissCat.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/28.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit

// cf. https://stackoverflow.com/a/46181337
// Thanks for Tung Fam
extension UIImage {
    func resized(widthUnder: CGFloat) -> UIImage? {
        return resized(withPercentage: widthUnder / size.width)
    }
    
    func resized(withPercentage percentage: CGFloat) -> UIImage? {
        let canvasSize = CGSize(width: size.width * percentage, height: size.height * percentage)
        UIGraphicsBeginImageContextWithOptions(canvasSize, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: canvasSize))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    func resizedTo5MB() -> UIImage? {
        guard let imageData = self.pngData() else { return nil }
        
        var resizingImage = self
        var imageSizeKB = Double(imageData.count) / 1000.0 // ! Or devide for 1024 if you need KB but not kB
        
        while imageSizeKB > 5000 { // ! Or use 1024 if you need KB but not kB
            guard let resizedImage = resizingImage.resized(withPercentage: 0.9),
                let imageData = resizedImage.pngData()
            else { return nil }
            
            resizingImage = resizedImage
            imageSizeKB = Double(imageData.count) / 1000.0 // ! Or devide for 1024 if you need KB but not kB
        }
        
        return resizingImage
    }
}

extension UIImage {
    // UIImageに対して適切な文字色を返す
    var opticalTextColor: UIColor {
        let ciColor = CIColor(color: averageColor)
        
        let red = ciColor.red * 255
        let green = ciColor.green * 255
        let blue = ciColor.blue * 255
        
        let target = red * 0.299 + green * 0.587 + blue * 0.114
        let threshold: CGFloat = 186
        
        if target < threshold / 2 {
            return .white
        } else if target < threshold {
            return .lightGray
        } else {
            return .black
        }
    }
    
    private var averageColor: UIColor {
        let rawImageRef: CGImage = cgImage!
        let data: CFData = rawImageRef.dataProvider!.data!
        let rawPixelData = CFDataGetBytePtr(data)
        
        let imageHeight = rawImageRef.height
        let imageWidth = rawImageRef.width
        let bytesPerRow = rawImageRef.bytesPerRow
        let stride = rawImageRef.bitsPerPixel / 6
        
        var red = 0
        var green = 0
        var blue = 0
        
        for row in 0 ... imageHeight {
            var rowPtr = rawPixelData! + bytesPerRow * row
            for _ in 0 ... imageWidth {
                red += Int(rowPtr[0])
                green += Int(rowPtr[1])
                blue += Int(rowPtr[2])
                rowPtr += Int(stride)
            }
        }
        
        let f: CGFloat = 1.0 / (255.0 * CGFloat(imageWidth) * CGFloat(imageHeight))
        return UIColor(red: f * CGFloat(red), green: f * CGFloat(green), blue: f * CGFloat(blue), alpha: 1.0)
    }
}
