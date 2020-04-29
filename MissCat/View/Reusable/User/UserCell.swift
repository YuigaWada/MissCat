//
//  UserCell.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/12.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxCocoa
import RxDataSources
import RxSwift
import SkeletonView
import UIKit

protocol UserCellDelegate {
    func tappedLink(text: String)
}

class UserCell: UITableViewCell, ComponentType, UITextViewDelegate {
    // MARK: I/O
    
    typealias Transformed = UserCell
    struct Arg {
        let icon: String?
        let shapedName: MFMString?
        let shapedDescription: MFMString?
    }
    
    // MARK: Views
    
    @IBOutlet weak var iconView: UIImageView!
    @IBOutlet weak var nameTextView: MisskeyTextView!
    @IBOutlet weak var descriptionTextView: MisskeyTextView!
    @IBOutlet weak var separatorView: UIView!
    
    // MARK: Vars
    
    var delegate: UserCellDelegate?
    
    private var viewModel: UserCellViewModel?
    private let disposeBag: DisposeBag = .init()
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        setupComponents()
        nameTextView.transformText()
        descriptionTextView.transformText()
    }
    
    func transform(isSkelton: Bool) -> UserCell {
        guard isSkelton else { return self }
        
        changeSkeltonState(on: true)
        
        return self
    }
    
    func transform(with arg: UserCell.Arg) -> UserCell {
        initialize()
        let input = UserCellViewModel.Input(icon: arg.icon,
                                            shapedName: arg.shapedName,
                                            shapedDescription: arg.shapedDescription,
                                            nameYanagi: nameTextView,
                                            descYanagi: descriptionTextView)
        
        let viewModel = UserCellViewModel(with: input, and: disposeBag)
        
        binding(viewModel)
        viewModel.transform()
        self.viewModel = viewModel
        return self
    }
    
    func initialize() {
        changeSkeltonState(on: false)
        
        iconView.image = nil
        nameTextView.attributedText = nil
        descriptionTextView.attributedText = nil
        
        nameTextView.resetViewString()
        descriptionTextView.resetViewString()
    }
    
    private func binding(_ viewModel: UserCellViewModel) {
        let output = viewModel.output
        
        output.icon
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(iconView.rx.image)
            .disposed(by: disposeBag)
        
        output.name
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(nameTextView.rx.attributedText)
            .disposed(by: disposeBag)
        
        output.description
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(descriptionTextView.rx.attributedText)
            .disposed(by: disposeBag)
        
        output.backgroundColor
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(rx.backgroundColor)
            .disposed(by: disposeBag)
        
        output.separatorBackgroundColor
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(separatorView.rx.backgroundColor)
            .disposed(by: disposeBag)
    }
    
    private func setupComponents() {
        iconView.layer.cornerRadius = iconView.frame.height / 2
        descriptionTextView.delegate = self
    }
    
    private func changeSkeltonState(on: Bool) {
        if on {
            backgroundColor = Theme.shared.currentModel?.colorPattern.ui.base ?? .white
            separatorView.backgroundColor = Theme.shared.currentModel?.colorPattern.ui.sub2 ?? .lightGray
            
            nameTextView.text = nil
            descriptionTextView.text = nil
            iconView.isSkeletonable = true
            
            let gradient = SkeletonGradient(baseColor: Theme.shared.currentModel?.colorPattern.ui.sub3 ?? .lightGray)
            iconView.showAnimatedGradientSkeleton(usingGradient: gradient)
            
            isUserInteractionEnabled = false // skelton表示されたセルはタップできないように
            
        } else {
            iconView.hideSkeleton()
            isUserInteractionEnabled = true
        }
    }
    
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        delegate?.tappedLink(text: URL.absoluteString)
        return false
    }
}

extension UserCell {
    class Model: IdentifiableType, Equatable {
        typealias Identity = String
        let identity: String = String(Float.random(in: 1 ..< 100))
        
        let isSkelton: Bool
        
        let userId: String?
        let icon: String?
        let name: String?
        let username: String?
        let description: String?
        
        var shapedName: MFMString?
        var shapedDescritpion: MFMString?
        
        init(isSkelton: Bool = false, userId: String, icon: String?, name: String?, username: String?, description: String?, shapedName: MFMString? = nil, shapedDescritpion: MFMString? = nil) {
            self.isSkelton = isSkelton
            self.userId = userId
            self.icon = icon
            self.name = name
            self.username = username
            self.description = description
            self.shapedName = shapedName
            self.shapedDescritpion = shapedDescritpion
        }
        
        static func == (lhs: UserCell.Model, rhs: UserCell.Model) -> Bool {
            return lhs.identity == rhs.identity
        }
        
        static func fakeSkeltonCell() -> UserCell.Model {
            return .init(isSkelton: true,
                         userId: "",
                         icon: nil,
                         name: nil,
                         username: nil,
                         description: nil)
        }
    }
    
    struct Section {
        var items: [Model]
    }
}

extension UserCell.Section: AnimatableSectionModelType {
    typealias Item = UserCell.Model
    typealias Identity = String
    
    var identity: String {
        return ""
    }
    
    init(original: UserCell.Section, items: [UserCell.Model]) {
        self = original
        self.items = items
    }
}
