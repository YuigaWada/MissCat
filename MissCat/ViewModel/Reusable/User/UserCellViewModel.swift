//
//  UserCellViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/13.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxCocoa
import RxSwift
import UIKit

class UserCellViewModel: ViewModelType {
    // MARK: I/O
    
    struct Input {
        let icon: String?
        let shapedName: MFMString?
        let shapedDescription: MFMString?
        let nameYanagi: YanagiText
        let descYanagi: YanagiText
    }
    
    struct Output {
        let icon: PublishRelay<UIImage> = .init()
        let name: PublishRelay<NSAttributedString?> = .init()
        let description: PublishRelay<NSAttributedString?> = .init()
        
        let backgroundColor: PublishRelay<UIColor> = .init()
        let separatorBackgroundColor: PublishRelay<UIColor> = .init()
    }
    
    struct State {}
    
    private let input: Input
    let output: Output = .init()
    
    private let disposeBag: DisposeBag
    
    init(with input: Input, and disposeBag: DisposeBag) {
        self.input = input
        self.disposeBag = disposeBag
    }
    
    func transform() {
        // icon
        if let icon = input.icon {
            icon.toUIImage { image in
                guard let image = image else { return }
                self.output.icon.accept(image)
            }
        }
        
        // name
        output.name.accept(input.shapedName?.attributed)
        input.shapedName?.mfmEngine.renderCustomEmojis(on: input.nameYanagi)
        
        // description
        output.description.accept(input.shapedDescription?.attributed)
        input.shapedDescription?.mfmEngine.renderCustomEmojis(on: input.nameYanagi)
        
        // color
        output.backgroundColor.accept(Theme.shared.currentModel?.colorPattern.ui.base ?? .white)
        output.separatorBackgroundColor.accept(Theme.shared.currentModel?.colorPattern.ui.sub2 ?? .lightGray)
    }
}
