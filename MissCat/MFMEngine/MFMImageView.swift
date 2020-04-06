//
//  MFMImageView.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/06.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import APNGKit
import Gifu
import SVGKit
import UIKit

class MFMImageView: UIImageView {
    private lazy var apngView: APNGImageView = {
        let apngView = APNGImageView()
        apngView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(apngView)
        self.setAutoLayout(to: apngView)
        return apngView
    }()
    
    private lazy var gifView: GIFImageView = {
        let gifView = GIFImageView()
        gifView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(gifView)
        self.setAutoLayout(to: gifView)
        return gifView
    }()
    
    // MARK: Publics
    
    ///  キャッシュを考慮してURLから画像データを取得し、非同期でsetされるようなUIImageViewを返す
    /// - Parameter imageUrl: 画像データのurl (アニメGIF / SVGも可)
    func setImage(url imageUrl: String, cachedToStorage: Bool = false) {
        if let cachedData = Cache.shared.getUrlData(on: imageUrl) { // キャッシュが存在する時
            setImage(data: cachedData)
        } else { // キャッシュが存在しない場合
            imageUrl.getData { data in
                guard let data = data else { return }
                Cache.shared.saveUrlData(data, on: imageUrl, toStorage: cachedToStorage) // キャッシュする
                self.setImage(data: data)
            }
        }
    }
    
    
    /// セルを再利用する際に呼ぶ
    func prepareForReuse() {
        gifView.prepareForReuse()
        gifView.gifImage = nil
        gifView.image = nil
        apngView.image = nil
        apngView.stopAnimating()
        image = nil
        backgroundColor = .darkGray
    }
    
    // MARK: Privates
    
    /// フォーマットを識別してImageをsetする
    /// - Parameter data: Data
    private func setImage(data: Data) {
        let format = getImageFormat(data)
        switch format {
        case .gif:
            setGifuImage(with: data)
        case .apng:
            setApngImage(with: data)
        case .png:
            setUIImage(with: data)
        case .other:
            setUIImage(with: data)
        }
    }
    
    
    /// ApngフォーマットのImageをset
    /// - Parameter data: Data
    private func setApngImage(with data: Data) {
        DispatchQueue.main.async {
            let apngImage = APNGImage(data: data)
            self.apngView.image = apngImage
            self.apngView.startAnimating()
            self.backgroundColor = .clear
        }
    }
    
    /// アニメーションGifに対応するため、非同期にGifuへ画像をsetする
    /// - Parameters:
    ///   - data: 画像データ
    ///   - imageView: set対象のGIFImageView
    private func setGifuImage(with data: Data) {
        DispatchQueue.main.async {
            self.gifView.animate(withGIFData: data) {
                DispatchQueue.main.async {
                    self.backgroundColor = .clear
                }
            }
        }
    }
    
    /// 非同期で画像をimageViewにsetする
    /// - Parameters:
    ///   - data: 画像データ
    ///   - imageView: set対象のGIFImageView
    private func setUIImage(with data: Data) {
        DispatchQueue.global().async {
            if let image = UIImage(data: data) {
                DispatchQueue.main.async {
                    self.backgroundColor = .clear
                    self.image = image
                }
            } else { // Type: SVG
                guard let svgKitImage = SVGKImage(data: data), let svgImage = svgKitImage.uiImage else { return }
                DispatchQueue.main.async {
                    self.backgroundColor = .clear
                    self.image = svgImage
                }
            }
        }
    }
    
    // MARK: Utilities
    
    /// Imageのフォーマットを返す
    /// - Parameter data: Data
    private func getImageFormat(_ data: Data) -> Format {
        guard let string = String(data: data, encoding: .isoLatin1) else { return .other }
        
        // apngについて参考に → https://stackoverflow.com/a/4525194
        let prefix = String(string.prefix(40))
        if prefix.contains("PNG") {
            return prefix.contains("acTL") ? .apng : .png
        } else if prefix.contains("GIF87a") || prefix.contains("GIF89a") {
            return .gif
        }
        return .other
    }
    
    private func setAutoLayout(to view: UIView) {
        addConstraints([
            NSLayoutConstraint(item: view,
                               attribute: .width,
                               relatedBy: .equal,
                               toItem: self,
                               attribute: .width,
                               multiplier: 1.0,
                               constant: 0),
            
            NSLayoutConstraint(item: view,
                               attribute: .height,
                               relatedBy: .equal,
                               toItem: self,
                               attribute: .height,
                               multiplier: 1.0,
                               constant: 0),
            
            NSLayoutConstraint(item: view,
                               attribute: .centerX,
                               relatedBy: .equal,
                               toItem: self,
                               attribute: .centerX,
                               multiplier: 1.0,
                               constant: 0),
            
            NSLayoutConstraint(item: view,
                               attribute: .centerY,
                               relatedBy: .equal,
                               toItem: self,
                               attribute: .centerY,
                               multiplier: 1.0,
                               constant: 0)
        ])
    }
}

extension MFMImageView {
    enum Format {
        case gif
        case apng
        case png
        case other
    }
}
