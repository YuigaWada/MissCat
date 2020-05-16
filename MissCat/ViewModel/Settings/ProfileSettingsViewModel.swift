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
    enum ImageTarget {
        case icon
        case banner
    }
    
    struct Input {
        let iconUrl: String?
        let bannerUrl: String?
        
        let name: String
        let description: String
        let isCat: Bool
        
        let rightNavButtonTapped: ControlEvent<Void>
        let iconTapped: ControlEvent<UITapGestureRecognizer>
        let bannerTapped: ControlEvent<UITapGestureRecognizer>
        let selectedImage: Observable<UIImage>
    }
    
    struct Output {
        let icon: PublishRelay<UIImage> = .init()
        let banner: PublishRelay<UIImage> = .init()
        
        let name: PublishRelay<String> = .init()
        let description: PublishRelay<String> = .init()
        let isCat: PublishRelay<Bool> = .init()
        
        let showSaveAlertTrigger: PublishRelay<Void> = .init()
        let pickImageTrigger: PublishRelay<Void> = .init()
    }
    
    class State {
        var hasEdited: Bool = false
        var currentTarget: ImageTarget?
    }
    
    class Changed {
        var icon: UIImage?
        var banner: UIImage?
        
        var name: String?
        var description: String?
        var isCat: Bool?
        
        var hasChanged: Bool {
            let emptyIcon = icon == nil
            let emptyBanner = banner == nil
            let emptyName = name == nil
            let emptyDesc = description == nil
            let emptyCat = isCat == nil
            return !(emptyIcon && emptyBanner && emptyName && emptyDesc && emptyCat)
        }
    }
    
    private let model = ProfileSettingsModel()
    private let input: Input
    let output: Output = .init()
    let state: State = .init()
    private let changed: Changed = .init()
    
    private let disposeBag: DisposeBag
    
    init(with input: Input, and disposeBag: DisposeBag) {
        self.input = input
        self.disposeBag = disposeBag
    }
    
    func transform() {
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
        
        // tap event
        input.rightNavButtonTapped.subscribe(onNext: { _ in
            self.model.save(diff: self.changed)
        }).disposed(by: disposeBag)
        
        input.iconTapped.subscribe(onNext: { _ in
            self.state.currentTarget = .icon
            self.output.pickImageTrigger.accept(())
        }).disposed(by: disposeBag)
        
        input.bannerTapped.subscribe(onNext: { _ in
            self.state.currentTarget = .banner
            self.output.pickImageTrigger.accept(())
        }).disposed(by: disposeBag)
        
        input.selectedImage.subscribe(onNext: { image in
            guard let target = self.state.currentTarget else { return }
            switch target {
            case .icon:
                self.output.icon.accept(image)
                self.changed.icon = image
            case .banner:
                self.output.banner.accept(image)
                self.changed.banner = image
            }
            
            self.state.currentTarget = nil
        }).disposed(by: disposeBag)
    }
}
