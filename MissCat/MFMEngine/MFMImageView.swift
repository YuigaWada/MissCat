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
    private var imageUrl: String?
    private var imageCompletion: ((Bool) -> Void)?
    
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
    func setImage(
        url imageUrl: String,
        cachedToStorage: Bool = false,
        completion: ((Bool) -> Void)? = nil
    ) {
        imageCompletion?(false)
        self.imageUrl = imageUrl
        imageCompletion = completion
        if let cachedData = Cache.shared.getUrlData(on: imageUrl), // キャッシュが存在する時
           imageUrl == self.imageUrl
        {
            setImage(data: cachedData, sourceURL: imageUrl)
        } else if let url = URL(string: imageUrl), url.isFileURL {
            DispatchQueue.global(qos: .userInitiated).async {
                let data = try? Data(contentsOf: url)
                guard self.imageUrl == imageUrl, let data else {
                    self.finishLoading(imageUrl, succeeded: false)
                    return
                }
                self.setImage(data: data, sourceURL: imageUrl)
            }
        } else { // キャッシュが存在しない場合
            imageUrl.getData { data in
                guard let data = data else {
                    self.finishLoading(imageUrl, succeeded: false)
                    return
                }
                if self.imageUrl == imageUrl { // 二回呼び出されて別の画像を表示しようとしてないか？
                    Cache.shared.saveUrlData(data, on: imageUrl, toStorage: cachedToStorage) // キャッシュする
                    self.setImage(data: data, sourceURL: imageUrl)
                } else {
                    self.finishLoading(imageUrl, succeeded: false)
                }
            }
        }
    }
    
    /// セルを再利用する際に呼ぶ
    func prepareForReuse() {
        imageCompletion?(false)
        imageCompletion = nil
        imageUrl = nil
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
    private func setImage(data: Data, sourceURL: String) {
        DispatchQueue.global().async {
            let format = Self.imageFormat(data)
            switch format {
            case .gif:
                self.setGifuImage(with: data, sourceURL: sourceURL)
            case .apng:
                self.setApngImage(with: data, sourceURL: sourceURL)
            case .png:
                self.setUIImage(with: data, sourceURL: sourceURL)
            case .other:
                self.setUIImage(with: data, sourceURL: sourceURL)
            }
        }
    }
    
    /// ApngフォーマットのImageをset
    /// - Parameter data: Data
    private func setApngImage(with data: Data, sourceURL: String) {
        DispatchQueue.main.async {
            let apngImage = APNGImage(data: data, progressive: true)
            self.apngView?.image = apngImage
            self.apngView?.startAnimating()
            self.backgroundColor = .clear
            self.finishLoading(sourceURL, succeeded: apngImage != nil)
        }
    }
    
    /// アニメーションGifに対応するためGifuへ画像をsetする
    /// - Parameters:
    ///   - data: 画像データ
    ///   - imageView: set対象のGIFImageView
    private func setGifuImage(with data: Data, sourceURL: String) {
        DispatchQueue.main.async {
            self.gifView?.animate(withGIFData: data, preparationBlock: {
                DispatchQueue.main.async {
                    self.backgroundColor = .clear
                    self.finishLoading(sourceURL, succeeded: true)
                }
            })
        }
    }
    
    /// 画像をimageViewにsetする
    /// - Parameters:
    ///   - data: 画像データ
    ///   - imageView: set対象のGIFImageView
    private func setUIImage(with data: Data, sourceURL: String) {
        if let image = UIImage(data: data) {
            DispatchQueue.main.async {
                self.backgroundColor = .clear
                self.image = image
                self.finishLoading(sourceURL, succeeded: true)
            }
        } else { // Type: SVG
            guard let svgKitImage = SVGKImage(data: data), let svgImage = svgKitImage.uiImage else {
                finishLoading(sourceURL, succeeded: false)
                return
            }
            DispatchQueue.main.async {
                self.backgroundColor = .clear
                self.image = svgImage
                self.finishLoading(sourceURL, succeeded: true)
            }
        }
    }

    private func finishLoading(_ sourceURL: String, succeeded: Bool) {
        DispatchQueue.main.async {
            guard self.imageUrl == sourceURL else { return }
            let completion = self.imageCompletion
            self.imageCompletion = nil
            completion?(succeeded)
        }
    }
    
    // MARK: Utilities
    
    /// Imageのフォーマットを返す
    /// - Parameter data: Data
    static func imageFormat(_ data: Data) -> Format {
        let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        if data.starts(with: pngSignature) {
            // acTL can legally follow ancillary chunks, so a fixed 40-byte prefix
            // misclassifies valid APNG files. Search the bounded chunk header area.
            let headerEnd = min(data.count, 4_096)
            let animationControl = Data("acTL".utf8)
            return data.range(of: animationControl, in: 8 ..< headerEnd) == nil ? .png : .apng
        }

        let signature = String(data: data.prefix(6), encoding: .ascii)
        if signature == "GIF87a" || signature == "GIF89a" {
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
    enum Format: Equatable {
        case gif
        case apng
        case png
        case other
    }
}
