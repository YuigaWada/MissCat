//
//  NavBarViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/06/10.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxCocoa
import RxSwift

class NavBarViewModel: ViewModelType {
    struct Icon {
        let owner: SecureUser
        let image: UIImage
    }
    
    struct Input {}
    struct Output {
        let userIcon: PublishRelay<UIImage> = .init()
    }
    
    struct State {}
    
    private let input: Input?
    var output: Output = .init()
    private let disposeBag: DisposeBag
    
    private let model = NavBarModel()
    private var iconImages: [Icon] = []
    
    init(with input: Input?, and disposeBag: DisposeBag) {
        self.input = input
        self.disposeBag = disposeBag
    }
    
    func transform(user: SecureUser) {
        let users = iconImages.filter { $0.owner.userId == user.userId } // アイコンのキャッシュを確認する
        
        if users.count > 0 {
            output.userIcon.accept(users[0].image)
        } else { // キャッシュがない場合
            guard let misskey = MisskeyKit(from: user) else { return }
            
            model.getIconImage(from: misskey) { image in
                let icon = Icon(owner: user, image: image)
                
                self.output.userIcon.accept(image)
                self.iconImages.append(icon)
            }
        }
    }
}
