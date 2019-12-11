//
//  PostViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/21.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxSwift

public class PostViewModel {
    
    public var iconImage: PublishSubject<UIImage> = .init()
    public var isSuccess: PublishSubject<Bool> = .init()
    
    private let model = PostModel()
    private var disposeBag: DisposeBag
    private var fileIds: [String] = []
    
    init(disposeBag: DisposeBag) {
        self.disposeBag = disposeBag
        
        model.getIconImage { image in
            guard let image = image else { return }
            self.iconImage.onNext(image)
        }
    }
    
    public func submitNote(_ note: String) {
        let fileIds = self.fileIds.count > 0 ? self.fileIds : nil
        
        self.model.submitNote(note, fileIds: fileIds){
            self.isSuccess.onNext($0)
        }
    }
    
    public func getLocation() {
        
    }
    
    public func pickImage(on view: UIViewController, type: UIImagePickerController.SourceType) {

        
        
    }
    
    
    public func uploadFile(_ image: UIImage, completion: @escaping (String?)->()) {
        self.model.uploadFile(image) { fileId in
            guard let fileId = fileId else { return }
            self.fileIds.append(fileId)
        }
    }
    
}
