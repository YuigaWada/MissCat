//
//  GIFImageView+MissCat.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/02/23.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Gifu
import SVGKit
import UIKit

// https://github.com/kaishin/Gifu/blob/d9b13cb2aaa2f0ac1fde4039aa4a4f87efdef29e/Sources/Gifu/Classes/GIFAnimatable.swift#L87
extension GIFImageView {
    ///  キャッシュを考慮してURLから画像データを取得し、非同期でsetされるようなUIImageViewを返す。
    /// - Parameter imageUrl: 画像データのurl (アニメGIF / SVGも可)s
    public func setImage(url imageUrl: String) {
        let isGif = self.isGif(url: imageUrl)
        if let cachedData = Cache.shared.getUrlData(on: imageUrl) { // キャッシュが存在する時
            if isGif {
                setGifuImage(with: cachedData)
            } else {
                setUIImage(with: cachedData)
            }
        } else { // キャッシュが存在しない場合
            imageUrl.getData { data in
                guard let data = data else { return }
                Cache.shared.saveUrlData(data, on: imageUrl) // キャッシュする
                
                if isGif {
                    self.setGifuImage(with: data)
                } else {
                    self.setUIImage(with: data)
                }
            }
        }
    }
    
    /// GIFイメージかどうかを判別する
    /// - Parameter url: URL
    private func isGif(url: String) -> Bool {
        return url.ext == "gif"
    }
    
    /// アニメーションGifに対応するため、非同期にGifuへ画像をsetする
    /// - Parameters:
    ///   - data: 画像データ
    ///   - imageView: set対象のGIFImageView
    private func setGifuImage(with data: Data) {
        DispatchQueue.main.async {
            self.animate(withGIFData: data) {
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
        if let image = UIImage(data: data) {
            DispatchQueue.main.async {
                self.backgroundColor = .clear
                self.image = image
            }
        } else { // Type: SVG
            guard let svgImage = SVGKImage(data: data) else { return }
            DispatchQueue.main.async {
                self.backgroundColor = .clear
                self.image = svgImage.uiImage
            }
        }
    }
}
