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

public class FileContainerCell: UICollectionViewCell {
    @IBOutlet weak var imageView: FileView!
    
    private let disposeBag = DisposeBag()
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setComponent()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setComponent()
    }
    
    public override func layoutSubviews() {
        imageView.contentMode = .scaleAspectFill
        super.layoutSubviews()
    }
    
    private func setComponent() {
        backgroundColor = .lightGray
    }
    
    public func setImage(with fileModel: FileContainer.Model, and delegate: NoteCellDelegate?) {
        imageView.backgroundColor = .clear
        imageView.image = fileModel.image
        imageView.isHidden = false
        imageView.setPlayIconImage(hide: !fileModel.isVideo)
        imageView.setNSFW(hide: !fileModel.isSensitive)
    }
}
