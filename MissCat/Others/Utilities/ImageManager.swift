//
//  ImageManager.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/23.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit
import RxSwift
import Photos
import CloudKit


// cf. https://qiita.com/KosukeOhmura/items/b5986bfe9a8b6778ffc8
// Thanks for @KosukeOhmura.
public class ImageManager {
    
    // 権限確認 -> 選択された画像のストリーム
    func pick(on viewController: UIViewController, sourceType: UIImagePickerController.SourceType) -> Observable<Result<UIImage, Error>> {
        return self.authorizedSourceType(sourceType)
            // 画像選択画面作成
            .map { sourceType -> (picker: UIImagePickerController, delegate: ImagePickerControllerDelegate) in
                // UIImagePickerControllerとそれにわたすdelegateを生成
                let picker = UIImagePickerController()
                let delegate = ImagePickerControllerDelegate()
                picker.delegate = delegate
                picker.allowsEditing = false
                picker.sourceType = sourceType
                return (picker, delegate)
        }
        .subscribeOn(MainScheduler.instance)
            // 表示
            .do(onNext: { [weak viewController] (picker, _) in
                DispatchQueue.main.async { viewController?.present(picker, animated: true) }
            })
            // 選択された画像のストリームをResultで
            .flatMap { (picker, delegate) -> Observable<Result<UIImage, Error>> in
                return delegate.pickedResultSubject
                    .do(onNext: { _ in picker.dismiss(animated: true) })
                    .map { result -> Result<UIImage, Error> in
                        return .success(result)
                }
        }
        
    }
    
    // 承認された画像ソースタイプのストリーム
    // 長いので別ストリームとして切り出した
    private func authorizedSourceType(_ sourceType: UIImagePickerController.SourceType) -> Observable<UIImagePickerController.SourceType> {
        return Observable<UIImagePickerController.SourceType>.create { observer -> Disposable in
            switch sourceType {
            case .photoLibrary:
                // フォトライブラリ
                let status = PHPhotoLibrary.authorizationStatus()
                switch status {
                case .authorized:
                    // 承認されていればそのまま返す
                    observer.onNext(.photoLibrary)
                    observer.onCompleted()
                case .denied:
                    // 拒否
                    break
                case .notDetermined:
                    // 未承認 許可を求める
                    PHPhotoLibrary.requestAuthorization { status in
                        if .authorized == status {
                            observer.onNext(.photoLibrary)
                            observer.onCompleted()
                        }
                    }
                case .restricted:
                    // アクセス許可制限
                    break
                    
                @unknown default:
                    break
                }
            case .camera:
                // カメラ
                let status = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
                switch status {
                case .authorized:
                    // 承認
                    observer.onNext(.camera)
                    observer.onCompleted()
                case .denied:
                    // 拒否
                    break
                case .notDetermined:
                    // 未承認 許可を求める
                    AVCaptureDevice.requestAccess(for: AVMediaType.video) { authorized in
                        if authorized {
                            observer.onNext(.camera)
                            observer.onCompleted()
                        }
                    }
                case .restricted:
                    // アクセス許可制限
                    break
                @unknown default:
                    break
                }
            case .savedPhotosAlbum:
                // 実装しなかったので割愛。 .photoLibrary と同じようにできるはず
                break
            @unknown default:
                break
            }
            
            return Disposables.create {
                observer.onCompleted()
            }
        }
    }
}

// UIImagePickerControllerに渡すデリゲート
fileprivate final class ImagePickerControllerDelegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    // 選択された画像のストリーム
    let pickedResultSubject = PublishSubject<UIImage>()
    
    // MARK: - UIImagePickerControllerDelegate
    
    // 画像が選択された
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        // 自身のsubjectにイベントを流す
        if let image = info[UIImagePickerController.InfoKey.originalImage] as? UIImage {
            self.pickedResultSubject.onNext(image)
        }
    }
    
}
