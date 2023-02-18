//
//  FileContainerCell.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/23.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Agrume
import RxSwift
import UIKit

class FileContainerCell: UICollectionViewCell {
    @IBOutlet weak var imageView: FileView!
    
    private let disposeBag = DisposeBag()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setComponent()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setComponent()
    }
    
    override func layoutSubviews() {
        imageView.contentMode = .scaleAspectFill
        super.layoutSubviews()
    }
    
    private func setComponent() {
        backgroundColor = .lightGray
    }
    
    private func initialize() {
        setComponent()
        imageView.image = nil
    }
    
    func transform(with fileModel: FileContainer.Model, and delegate: NoteCellDelegate?) {
        initialize()
        
        let cached = Cache.shared.getUiImage(url: fileModel.originalUrl) ?? Cache.shared.getUiImage(url: fileModel.thumbnailUrl)
        if let cached = cached {
            setImage(image: cached,
                     originalUrl: fileModel.originalUrl,
                     isVideo: fileModel.isVideo,
                     isSensitive: fileModel.isSensitive)
            return
        }

        // キャッシュが存在しない場合
        
        fileModel.thumbnailUrl.toUIImage { image in
            guard let image = image else { return }
            
            Cache.shared.saveUiImage(image, url: fileModel.thumbnailUrl)
            
            self.setImage(image: image,
                          originalUrl: fileModel.originalUrl,
                          isVideo: fileModel.isVideo,
                          isSensitive: fileModel.isSensitive)
        }
        
        fileModel.originalUrl.toUIImage { image in
            guard let image = image else { return }
            
            Cache.shared.saveUiImage(image, url: fileModel.originalUrl)
            
            self.setImage(image: image,
                          originalUrl: fileModel.originalUrl,
                          isVideo: fileModel.isVideo,
                          isSensitive: fileModel.isSensitive)
        }
    }
    
    private func setImage(image: UIImage, originalUrl: String, isVideo: Bool, isSensitive: Bool) {
        DispatchQueue.main.async {
            self.imageView.backgroundColor = .clear
            self.imageView.image = image
            self.imageView.isHidden = false
            self.imageView.setPlayIconImage(hide: !isVideo)
            self.imageView.setNSFW(hide: !isSensitive)
        }
    }
}
