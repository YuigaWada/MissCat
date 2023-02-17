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

class MFMImageView: MissCatImageView {
    // MARK: Views
    
    private var apngView: APNGImageView?
    private var gifView: GIFImageView?
    
    // MARK: LifeCycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        apngView = setupApngView()
        gifView = setupGifView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        apngView = setupApngView()
        gifView = setupGifView()
    }
    
    private func setupApngView() -> APNGImageView {
        let apngView = APNGImageView()
        apngView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(apngView)
        setAutoLayout(to: apngView)
        return apngView
    }
    
    private func setupGifView() -> GIFImageView {
        let gifView = GIFImageView()
        gifView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gifView)
        setAutoLayout(to: gifView)
        return gifView
    }
    
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
        gifView?.prepareForReuse()
        gifView?.gifImage = nil
        gifView?.image = nil
        apngView?.image = nil
        apngView?.stopAnimating()
        image = nil
        backgroundColor = .darkGray
    }
    
    // MARK: Privates
    
    /// フォーマットを識別してImageをsetする
    /// - Parameter data: Data
    private func setImage(data: Data) {
        DispatchQueue.global().async {
            let format = self.getImageFormat(data)
            switch format {
            case .gif:
                self.setGifuImage(with: data)
            case .apng:
                self.setApngImage(with: data)
            case .png:
                self.setUIImage(with: data)
            case .other:
                self.setUIImage(with: data)
            }
        }
    }
    
    /// ApngフォーマットのImageをset
    /// - Parameter data: Data
    private func setApngImage(with data: Data) {
        DispatchQueue.main.async {
            let apngImage = APNGImage(data: data, progressive: true)
            self.apngView?.image = apngImage
            self.apngView?.startAnimating()
            self.backgroundColor = .clear
        }
    }
    
    /// アニメーションGifに対応するためGifuへ画像をsetする
    /// - Parameters:
    ///   - data: 画像データ
    ///   - imageView: set対象のGIFImageView
    private func setGifuImage(with data: Data) {
        DispatchQueue.main.async {
            self.gifView?.animate(withGIFData: data, animationBlock: {
                DispatchQueue.main.async {
                    self.backgroundColor = .clear
                }
            })
        }
    }
    
    /// 画像をimageViewにsetする
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
            guard let svgKitImage = SVGKImage(data: data), let svgImage = svgKitImage.uiImage else { return }
            DispatchQueue.main.async {
                self.backgroundColor = .clear
                self.image = svgImage
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
