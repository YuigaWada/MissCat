//
//  FileContainerViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/23.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxSwift

public class FileContainerViewModel: ViewModelType {
    // MARK: IO
    
    struct Input {}
    
    public struct Output {
        let files: PublishSubject<[FileContainer.Section]> = .init()
    }
    
    struct State {}
    
    public let output: Output = .init()
    
    public var fileModel: [FileContainer.Model] = []
    
    private let disposeBag: DisposeBag
    
    // MARK: Publics
    
    init(disposeBag: DisposeBag) {
        self.disposeBag = disposeBag
    }
    
    public func setFile(with arg: FileContainer.Arg) {
        guard arg.fileVisible else { return }
        if let files = Cache.shared.getFiles(noteId: arg.noteId) { // キャッシュが存在する場合
            for index in 0 ..< files.count {
                let file = files[index]
                fileModel.append(FileContainer.Model(image: file.thumbnail,
                                                     originalUrl: file.originalUrl,
                                                     isVideo: file.type == .Video,
                                                     isSensitive: file.isSensitive))
                updateFiles(new: fileModel)
            }
            return
        }
        // キャッシュが存在しない場合
        let files = arg.files
        let fileCount = files.count
        
        for index in 0 ..< fileCount {
            let file = files[index]
            let fileType = checkFileType(file.type)
            
            guard fileType != .Unknown,
                let thumbnailUrl = file.thumbnailUrl,
                let original = file.url else { break }
            
            if fileType == .Audio {
            } else {
                thumbnailUrl.toUIImage { image in
                    guard let image = image else { return }
                    
                    Cache.shared.saveFiles(noteId: arg.noteId,
                                           image: image,
                                           originalUrl: original,
                                           type: fileType,
                                           isSensitive: file.isSensitive ?? false)
                    
                    self.fileModel.append(FileContainer.Model(image: image,
                                                              originalUrl: original,
                                                              isVideo: fileType == .Video,
                                                              isSensitive: file.isSensitive ?? true))
                    self.updateFiles(new: self.fileModel)
                }
            }
        }
    }
    
    /// ファイルの種類を識別する
    /// - Parameter type: MIME Type
    public func checkFileType(_ type: String?) -> FileType {
        guard let type = type else { return .Unknown }
        
        if type.contains("video") {
            return .Video
        } else if type.contains("audio") {
            return .Audio
        }
        
        let isImage: Bool = type.contains("image")
        let isGif: Bool = type.contains("gif")
        
        return isImage ? (isGif ? .GIFImage : .PlaneImage) : .Unknown
    }
    
    private func updateFiles(new: [FileContainer.Model]) {
        updateFiles(new: [FileContainer.Section(items: new)])
    }
    
    private func updateFiles(new: [FileContainer.Section]) {
        output.files.onNext(new)
    }
}
