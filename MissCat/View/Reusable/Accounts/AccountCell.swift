//
//  AccountCell.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/06/08.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxCocoa
import RxDataSources
import RxSwift
import UIKit

class AccountCell: UITableViewCell, ComponentType {
    struct Arg {
        let user: SecureUser
    }
    
    enum State {
        case normal
        case editable
    }
    
    typealias Transformed = AccountCell
    
    @IBOutlet weak var iconImageView: MissCatImageView!
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var borderView: UIView!
    @IBOutlet weak var delButton: UIButton!
    
    @IBOutlet weak var usernameLabel: UILabel!
    @IBOutlet weak var instanceLabel: UILabel!
    
    lazy var deleteTrigger: Observable<Void> = self.delButton.rx.tap.asObservable()
    
    private let disposeBag: DisposeBag = .init()
    
    override func layoutSubviews() {
        setupComponent()
        bindTheme()
        setTheme()
    }
    
    // MARK: Design
    
    private func bindTheme() {
        let theme = Theme.shared.theme
        
        theme.map { $0.colorPattern.ui.text }.subscribe(onNext: { self.nameLabel.textColor = $0 }).disposed(by: disposeBag)
        theme.map { $0.colorPattern.ui.text }.subscribe(onNext: { self.usernameLabel.textColor = $0 }).disposed(by: disposeBag)
        theme.map { $0.colorPattern.ui.text }.subscribe(onNext: { self.instanceLabel.textColor = $0 }).disposed(by: disposeBag)
        
        theme.map { $0.mainColorHex }.subscribe(onNext: { mainColorHex in
            self.borderView.layer.borderColor = UIColor(hex: mainColorHex).cgColor
        }).disposed(by: disposeBag)
    }
    
    private func setTheme() {
        guard let theme = Theme.shared.currentModel else { return }
        
        let colorPattern = theme.colorPattern.ui
        nameLabel.textColor = colorPattern.text
        usernameLabel.textColor = colorPattern.text
        instanceLabel.textColor = colorPattern.text
        
        borderView.layer.borderColor = UIColor(hex: theme.mainColorHex).cgColor
    }
    
    func transform(with arg: Arg) -> AccountCell {
        let input = AccountCellViewModel.Input(user: arg.user)
        let viewModel = AccountCellViewModel(with: input, and: disposeBag)
        
        binding(with: viewModel)
        viewModel.transform()
        
        return self
    }
    
    func changeState(_ state: State) {
        switch state {
        case .normal:
            delButton.isHidden = true
        case .editable:
            delButton.isHidden = false
        }
    }
    
    private func setupComponent() {
        iconImageView.maskCircle()
        
        nameLabel.font = UIFont(name: "Helvetica", size: 15.0)
        usernameLabel.font = UIFont(name: "Helvetica", size: 10.0)
        instanceLabel.font = UIFont(name: "Helvetica", size: 13.0)
        
        borderView.layer.cornerRadius = 8
        borderView.layer.masksToBounds = true
        borderView.layer.borderWidth = 1
        backgroundColor = .clear
        
        let selectedView = UIView()
        selectedView.backgroundColor = .clear
        selectedBackgroundView = selectedView
    }
    
    private func binding(with viewModel: AccountCellViewModel) {
        let output = viewModel.output
        
        output.iconImage
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(iconImageView.rx.image)
            .disposed(by: disposeBag)
        
        output.name
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(nameLabel.rx.text)
            .disposed(by: disposeBag)
        
        output.username
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(usernameLabel.rx.text)
            .disposed(by: disposeBag)
        
        output.instance
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(instanceLabel.rx.text)
            .disposed(by: disposeBag)
    }
}

extension AccountCell {
    class Model: IdentifiableType, Equatable {
        internal init(owner: SecureUser) {
            self.owner = owner
        }
        
        typealias Identity = String
        let identity: String = String(Float.random(in: 1 ..< 100))
        
        var owner: SecureUser
        
        static func == (lhs: AccountCell.Model, rhs: AccountCell.Model) -> Bool {
            return lhs.identity == rhs.identity
        }
    }
    
    struct Section {
        var items: [Model]
    }
}

extension AccountCell.Section: AnimatableSectionModelType {
    typealias Item = AccountCell.Model
    typealias Identity = String
    
    var identity: String {
        return ""
    }
    
    init(original: AccountCell.Section, items: [AccountCell.Model]) {
        self = original
        self.items = items
    }
}
