//
//  UrlPreviewer.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/07.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxCocoa
import RxSwift
import UIKit

class UrlPreviewer: UIView, ComponentType {
    typealias Transformed = UrlPreviewer
    struct Arg {
        let url: String
        let owner: SecureUser?
    }
    
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var previewTextView: UITextView!
    
    private var viewModel: UrlPreviewerViewModel?
    private let disposeBag = DisposeBag()
    
    // MARK: Life Cycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        loadNib()
        setComponent()
        setTheme()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
        loadNib()
        setComponent()
        setTheme()
    }
    
    func loadNib() {
        if let view = UINib(nibName: "UrlPreviewer", bundle: Bundle(for: type(of: self))).instantiate(withOwner: self, options: nil)[0] as? UIView {
            view.frame = bounds
            view.backgroundColor = .clear
            addSubview(view)
        }
    }
    
    // MARK: Design
    
    private func setTheme() {
        guard let theme = Theme.shared.currentModel else { return }
        let colorPattern = theme.colorPattern.ui
        
        backgroundColor = colorPattern.sub2
        titleLabel.textColor = colorPattern.text
        previewTextView.textColor = colorPattern.sub0
    }
    
    // MARK: Setup
    
    private func binding(_ viewModel: UrlPreviewerViewModel) {
        let output = viewModel.output
        
        output.title
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(titleLabel.rx.text)
            .disposed(by: disposeBag)
        
        output.description
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(previewTextView.rx.text)
            .disposed(by: disposeBag)
        
        output.image
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: { image in
                self.imageView.image = image
                self.backgroundColor = .clear
            })
            .disposed(by: disposeBag)
    }
    
    private func setComponent() {
        layer.cornerRadius = 5
        layer.borderColor = UIColor.lightGray.cgColor
        layer.borderWidth = 0.3
        clipsToBounds = true
        
        imageView.backgroundColor = .lightGray
        imageView.contentMode = .scaleAspectFill
        previewTextView.textContainer.lineBreakMode = .byTruncatingTail
    }
    
    // MARK: Publics
    
    func transform(with arg: UrlPreviewer.Arg) -> UrlPreviewer {
        let viewModel = UrlPreviewerViewModel(with: .init(url: arg.url, owner: arg.owner), and: disposeBag)
        binding(viewModel)
        
        self.viewModel = viewModel
        return self
    }
    
    func initialize() {
        titleLabel.text = nil
        previewTextView.text = "Loading..."
        imageView.image = nil
        viewModel?.prepareForReuse()
    }
}
