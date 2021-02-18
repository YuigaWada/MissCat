//
//  UIViewController+PhotoEditor.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/12/16.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import AVKit
import iOSPhotoEditor
import RxSwift
import UIKit

extension UIViewController {
    func showPhotoEditor(with image: UIImage) -> Observable<UIImage?> {
        let rxPhotoEditor = RxPhotoEditor()
        
        return rxPhotoEditor.show(on: self, with: image)
    }
    
    fileprivate class RxPhotoEditor: UIViewController, PhotoEditorDelegate {
        private var observer: AnyObserver<UIImage?>?
        private var originalImage: UIImage?
        
        fileprivate func show(on viewController: UIViewController, with image: UIImage) -> Observable<UIImage?> {
            originalImage = image
            
            let photoEditor = PhotoEditorViewController(nibName: "PhotoEditorViewController", bundle: Bundle(for: PhotoEditorViewController.self))
            
            photoEditor.photoEditorDelegate = self
            photoEditor.image = image
            photoEditor.hiddenControls = [.share]
            photoEditor.colors = [.red, .blue, .green]
            
            viewController.presentOnFullScreen(photoEditor, animated: true, completion: nil)
            
            return Observable.create { observer in
                self.observer = observer
                return Disposables.create()
            }
        }
        
        func doneEditing(image: UIImage) {
            guard let observer = observer else { return }
            observer.onNext(image)
            observer.onCompleted()
        }
        
        func canceledEditing() {
            guard let observer = observer else { return }
            observer.onNext(originalImage)
            observer.onCompleted()
        }
    }
}

extension UIViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func pickImage(type: UIImagePickerController.SourceType, delegate: (UIImagePickerControllerDelegate & UINavigationControllerDelegate)? = nil) {
        if UIImagePickerController.isSourceTypeAvailable(.savedPhotosAlbum) {
            let picker = UIImagePickerController()
            picker.sourceType = type
            picker.mediaTypes = UIImagePickerController.availableMediaTypes(for: type) ?? []
            picker.videoQuality = .typeHigh
            picker.delegate = delegate ?? self
            
            presentOnFullScreen(picker, animated: true, completion: nil)
        }
    }
    
    func transformAttachment(disposeBag: DisposeBag, picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any], completion: @escaping (UIImage?, UIImage?, URL?) -> Void) {
        picker.dismiss(animated: true, completion: nil)
        
        let isImage = info[UIImagePickerController.InfoKey.originalImage] is UIImage
        
        if isImage {
            guard let originalImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage else { return }
            
            showPhotoEditor(with: originalImage).subscribe(onNext: { editedImage in // 画像エディタを表示
                guard let editedImage = editedImage else { return }
                completion(originalImage, editedImage, nil)
            }).disposed(by: disposeBag)
            
            return
        }
        // is Video
        guard let url = info[UIImagePickerController.InfoKey.mediaURL] as? NSURL else { return }
        AVAsset.convert2Mp4(videoUrl: url) { session in // 動画のデフォルトがmovなのでmp4に変換する
            guard session.status == .completed, let filePath = session.outputURL else { return }
            
            completion(nil, nil, filePath)
        }
    }
}
