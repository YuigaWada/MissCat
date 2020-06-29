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
    func tappedLink(text: String, owner: SecureUser)
}

class UserCell: UITableViewCell, ComponentType, UITextViewDelegate {
    // MARK: I/O
    
    typealias Transformed = UserCell
    struct Arg {
        let owner: SecureUser
        let icon: String?
        let shapedName: MFMString?
        let shapedDescription: MFMString?
    }
    
    // MARK: Views
    
    @IBOutlet weak var iconView: MissCatImageView!
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
        let input = UserCellViewModel.Input(owner: arg.owner,
                                            icon: arg.icon,
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
        iconView.maskCircle()
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
        guard let owner = viewModel?.state.owner else { return false }
        delegate?.tappedLink(text: URL.absoluteString, owner: owner)
        return false
    }
}

extension UserCell {
    class Model: CellModel {
        let type: ModelType
        let entity: UserEntity
        
        var shapedName: MFMString?
        var shapedDescritpion: MFMString?
        
        init(type: ModelType = .model, user entity: UserEntity = .mock, shapedName: MFMString? = nil, shapedDescritpion: MFMString? = nil) {
            self.type = type
            self.entity = entity
            self.shapedName = shapedName
            self.shapedDescritpion = shapedDescritpion
        }
    }
    
    enum ModelType {
        case model
        case skelton
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
