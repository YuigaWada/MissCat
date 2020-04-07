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
    }
    
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var previewTextView: UITextView!
    
    private let disposeBag = DisposeBag()
    
    // MARK: Life Cycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        loadNib()
        setComponent()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
        loadNib()
        setComponent()
    }
    
    func loadNib() {
        if let view = UINib(nibName: "UrlPreviewer", bundle: Bundle(for: type(of: self))).instantiate(withOwner: self, options: nil)[0] as? UIView {
            view.frame = bounds
            addSubview(view)
        }
    }
    
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
        layer.borderWidth = 1
        clipsToBounds = true
        
        imageView.backgroundColor = .lightGray
        imageView.contentMode = .scaleAspectFill
        previewTextView.textContainer.lineBreakMode = .byTruncatingTail
    }
    
    // MARK: Publics
    
    func transform(with arg: UrlPreviewer.Arg) -> UrlPreviewer {
        let viewModel = UrlPreviewerViewModel(with: .init(url: arg.url), and: disposeBag)
        binding(viewModel)
        return self
    }
    
    func initialize() {
        titleLabel.text = nil
        previewTextView.text = "Loading..."
        imageView.image = nil
    }
}
