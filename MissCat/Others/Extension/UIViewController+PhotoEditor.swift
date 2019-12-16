//
//  UIViewController+PhotoEditor.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/12/16.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit
import iOSPhotoEditor
import RxSwift

extension UIViewController {
    
    func showPhotoEditor(with image: UIImage)-> Observable<UIImage?> {
        let rxPhotoEditor = RxPhotoEditor()
        
        return rxPhotoEditor.show(on: self, with: image)
    }
    
    
    fileprivate class RxPhotoEditor: UIViewController, PhotoEditorDelegate {
        
        private var observer: AnyObserver<UIImage?>?
        private var originalImage: UIImage?
        
        fileprivate func show(on viewController: UIViewController, with image: UIImage)-> Observable<UIImage?> {
            self.originalImage = image
            
            let photoEditor = PhotoEditorViewController(nibName:"PhotoEditorViewController",bundle: Bundle(for: PhotoEditorViewController.self))
            
            photoEditor.photoEditorDelegate = self
            photoEditor.image = image
            photoEditor.hiddenControls = [.share]
            photoEditor.colors = [.red,.blue,.green]
            
            viewController.present(photoEditor, animated: true, completion: nil)
            
            return Observable.create() { observer in
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
