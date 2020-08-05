//
//  UIViewController+ImageViewer.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/08/05.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Agrume
import RxSwift
import UIKit

extension UIViewController {
    func viewImage(urls: [URL], startIndex: Int, disposeBag: DisposeBag) {
        let overlayView = AgrumeOverlay()
        let agrume = Agrume(urls: urls, startIndex: startIndex, background: .blurred(.dark), overlayView: overlayView)
        
        overlayView.shareTrigger?.subscribe(onNext: { _ in // 共有
            agrume.image(forIndex: agrume.currentIndex) { image in
                guard let image = image else { return }
                let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
                agrume.present(activityVC, animated: true, completion: nil)
            }
        }).disposed(by: disposeBag)
        
        agrume.show(from: self) // 画像を表示
    }
    
    func viewImage(image: UIImage, disposeBag: DisposeBag) {
        let overlayView = AgrumeOverlay()
        let agrume = Agrume(image: image, background: .blurred(.dark), overlayView: overlayView)
        
        overlayView.shareTrigger?.subscribe(onNext: { _ in // 共有
            agrume.image(forIndex: agrume.currentIndex) { image in
                guard let image = image else { return }
                let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
                agrume.present(activityVC, animated: true, completion: nil)
            }
        }).disposed(by: disposeBag)
        
        agrume.show(from: self) // 画像を表示
    }
}

class AgrumeOverlay: AgrumeOverlayView {
    var shareTrigger: Observable<Void>?
    
    lazy var toolbar: UIToolbar = {
        let toolbar = UIToolbar()
        let flexibleItem = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let shareItem = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: nil)
        
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.barStyle = .blackTranslucent
        toolbar.setItems([
            flexibleItem,
            shareItem,
        ], animated: false)
        
        self.shareTrigger = shareItem.rx.tap.asObservable()
        return toolbar
    }()
    
    var portableSafeLayoutGuide: UILayoutGuide {
        if #available(iOS 11.0, *) {
            return safeAreaLayoutGuide
        }
        return layoutMarginsGuide
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        addSubview(toolbar)
        
        NSLayoutConstraint.activate([
            toolbar.bottomAnchor.constraint(equalTo: portableSafeLayoutGuide.bottomAnchor),
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
}
