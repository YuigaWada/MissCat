//
//  ProfileSettingsViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/05/14.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Foundation
import RxCocoa
import RxSwift
import UIKit

class ProfileSettingsViewModel: ViewModelType {
    struct Input {
        let iconUrl: String?
        let bannerUrl: String?
        
        let name: String
        let description: String
        let isCat: Bool
    }
    
    struct Output {
        let icon: PublishRelay<UIImage> = .init()
        let banner: PublishRelay<UIImage> = .init()
        
        let name: PublishRelay<String> = .init()
        let description: PublishRelay<String> = .init()
        let isCat: PublishRelay<Bool> = .init()
    }
    
    struct State {}
    
//    private let model = ProfileSettingsModel()
    private let input: Input
    let output: Output = .init()
    
    private let disposeBag: DisposeBag
    
    init(with input: Input, and disposeBag: DisposeBag) {
        self.input = input
        self.disposeBag = disposeBag
        
        binding()
    }
    
    private func binding() {
        // image
        _ = input.iconUrl?.toUIImage { image in
            guard let image = image else { return }
            self.output.icon.accept(image)
        }
        
        _ = input.bannerUrl?.toUIImage { image in
            guard let image = image else { return }
            self.output.banner.accept(image)
        }
        
        // text
        output.name.accept(input.name)
        output.description.accept(input.description)
        
        // bool
        output.isCat.accept(input.isCat)
    }
}
