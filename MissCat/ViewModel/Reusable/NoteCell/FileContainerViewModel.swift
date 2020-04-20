//
//  FileContainerViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/23.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxSwift

class FileContainerViewModel: ViewModelType {
    // MARK: IO
    
    struct Input {}
    
    struct Output {
        let files: PublishSubject<[FileContainer.Section]> = .init()
    }
    
    struct State {}
    
    let output: Output = .init()
    
    var fileModel: [FileContainer.Model] = []
    
    private let disposeBag: DisposeBag
    
    // MARK: Publics
    
    init(disposeBag: DisposeBag) {
        self.disposeBag = disposeBag
    }
    
    /// モデルをsetする
    func setFileModel(with arg: FileContainer.Arg) {
        guard arg.fileVisible else { return }
        
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
                fileModel.append(FileContainer.Model(thumbnailUrl: thumbnailUrl,
                                                     originalUrl: original,
                                                     isVideo: fileType == .Video,
                                                     isSensitive: file.isSensitive ?? true))
            }
        }
        updateFiles(new: fileModel)
    }
    
    func initialize() {
        fileModel = []
        updateFiles(new: fileModel)
    }
    
    /// ファイルの種類を識別する
    /// - Parameter type: MIME Type
    func checkFileType(_ type: String?) -> FileType {
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
