//
//  UrlPreviewerViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/07.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxCocoa
import RxSwift
import SwiftLinkPreview

class UrlPreviewerViewModel: ViewModelType {
    struct Input {
        let url: String
        let owner: SecureUser?
    }
    
    struct Output {
        let title: PublishRelay<String> = .init()
        let description: PublishRelay<String> = .init()
        let image: PublishRelay<UIImage> = .init()
    }
    
    struct State {}
    
    private let input: Input
    let output = Output()
    
    private let model = UrlPreviewerModel()
    private let disposeBag: DisposeBag
    private var imageSessionTasks: [URLSessionDataTask] = []
    
    init(with input: Input, and disposeBag: DisposeBag) {
        self.input = input
        self.disposeBag = disposeBag
        getPreview()
    }
    
    func prepareForReuse() {
        imageSessionTasks.forEach { task in
            task.cancel()
        }
        imageSessionTasks.removeAll()
    }
    
    // MARK: Privates
    
    /// プレビューを取得
    private func getPreview() {
        model.getPreview(of: input.url, instance: input.owner?.instance ?? "misskey.io") { res in
            self.output.title.accept(res.title ?? "No Title")
            self.output.description.accept(res.description ?? "No Description")
            if let imageUrl = res.thumbnail {
                self.getImage(from: imageUrl)
            }
        }
    }
    
    /// urlからプレビューimageを取得
    /// - Parameter url: URL
    private func getImage(from url: String) {
        if let cache = Cache.shared.getUiImage(url: url) {
            output.image.accept(cache)
            return
        }
        
        let task = url.toUIImage {
            guard let image = $0 else { return }
            self.output.image.accept(image)
            Cache.shared.saveUiImage(image, url: url)
        }
        
        if let task = task {
            imageSessionTasks.append(task)
        }
    }
}
