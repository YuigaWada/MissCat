//
//  ProfileSettingsViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/05/14.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Eureka
import Foundation
import RxCocoa
import RxSwift
import UIKit
import MisskeyKit

// プロフィールの差分を表す
class ChangedProfile {
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

class ProfileSettingsViewModel: ViewModelType {
    enum ImageTarget {
        case icon
        case banner
    }
    
    struct Input {
        let owner: SecureUser?
        let needLoadIcon: Bool
        let needLoadBanner: Bool
        
        let iconUrl: String?
        let bannerUrl: String?
        
        let currentName: String
        let currentDescription: String
        let currentCatState: Bool
        
        let rxName: ControlProperty<String?>
        let rxDesc: ControlProperty<String?>
        let rxCat: ControlProperty<Bool?>
        
        let rightNavButtonTapped: ControlEvent<Void>
        let iconTapped: ControlEvent<UITapGestureRecognizer>
        let bannerTapped: ControlEvent<UITapGestureRecognizer>
        let selectedImage: Observable<UIImage>
        let resetImage: Observable<Void>
        let overrideInfoTrigger: PublishRelay<ChangedProfile>
    }
    
    struct Output {
        let icon: PublishRelay<UIImage> = .init()
        let banner: PublishRelay<UIImage> = .init()
        
        let name: PublishRelay<String> = .init()
        let description: PublishRelay<String> = .init()
        let isCat: PublishRelay<Bool> = .init()
        
        let showSaveAlertTrigger: PublishRelay<Void> = .init()
        let pickImageTrigger: PublishRelay<Bool> = .init() // Bool: hasChanged
        let popViewControllerTrigger: PublishRelay<Void> = .init()
    }
    
    class State {
        var hasEdited: Bool = false
        var currentTarget: ImageTarget?
        var changed: ChangedProfile = .init()
    }
    
    private lazy var misskey: MisskeyKit? = {
          guard let owner = input.owner else { return nil }
          return MisskeyKit(from: owner)
      }()
    private lazy var model = ProfileSettingsModel(from: misskey)
    private let input: Input
    let output: Output = .init()
    let state: State = .init()
    
    private let disposeBag: DisposeBag
    
    init(with input: Input, and disposeBag: DisposeBag) {
        self.input = input
        self.disposeBag = disposeBag
    }
    
    func transform() {
        // image
        if input.needLoadIcon { setDefaultIcon() }
        
        if input.needLoadBanner { setDefaultBanner() }
        
        // input
        input.rxName.subscribe(onNext: { name in
            let hasChanged = name != self.input.currentName
            self.state.changed.name = hasChanged ? name : nil
        }).disposed(by: disposeBag)
        
        input.rxDesc.subscribe(onNext: { desc in
            let hasChanged = desc != self.input.currentDescription
            self.state.changed.description = hasChanged ? desc : nil
        }).disposed(by: disposeBag)
        
        input.rxCat.subscribe(onNext: { isCat in
            let hasChanged = isCat != self.input.currentCatState
            self.state.changed.isCat = hasChanged ? isCat : nil
        }).disposed(by: disposeBag)
        
        // tap event
        input.rightNavButtonTapped.subscribe(onNext: { _ in
            self.model.save(diff: self.state.changed)
            self.output.popViewControllerTrigger.accept(())
            
            if self.state.changed.hasChanged {
                self.input.overrideInfoTrigger.accept(self.state.changed)
            }
        }).disposed(by: disposeBag)
        
        input.iconTapped.subscribe(onNext: { _ in
            self.state.currentTarget = .icon
            let hasChanged = self.state.changed.icon != nil
            self.output.pickImageTrigger.accept(hasChanged)
        }).disposed(by: disposeBag)
        
        input.bannerTapped.subscribe(onNext: { _ in
            self.state.currentTarget = .banner
            let hasChanged = self.state.changed.banner != nil
            self.output.pickImageTrigger.accept(hasChanged)
        }).disposed(by: disposeBag)
        
        // trigger
        input.selectedImage.subscribe(onNext: { image in
            guard let target = self.state.currentTarget else { return }
            switch target {
            case .icon:
                self.output.icon.accept(image)
                self.state.changed.icon = image
            case .banner:
                self.output.banner.accept(image)
                self.state.changed.banner = image
            }
            
            self.state.currentTarget = nil
        }).disposed(by: disposeBag)
        
        input.resetImage.subscribe(onNext: { _ in
            guard let target = self.state.currentTarget else { return }
            switch target {
            case .icon:
                self.setDefaultIcon()
                self.state.changed.icon = nil
            case .banner:
                self.setDefaultBanner()
                self.state.changed.banner = nil
            }
            
            self.state.currentTarget = nil
        }).disposed(by: disposeBag)
    }
    
    private func setDefaultBanner() {
        _ = input.bannerUrl?.toUIImage { image in
            guard let image = image else { return }
            self.output.banner.accept(image)
        }
    }
    
    private func setDefaultIcon() {
        _ = input.iconUrl?.toUIImage { image in
            guard let image = image else { return }
            self.output.icon.accept(image)
        }
    }
}
