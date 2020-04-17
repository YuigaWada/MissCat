//
//  DirectMessageViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/16.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxCocoa
import RxSwift
import UIKit

class DirectMessageViewController: ChatViewController {
    private var viewModel: DirectMessageViewModel?
    private let disposeBag = DisposeBag()
    
    func setup(userId: String? = nil, groupId: String? = nil) {
        let viewModel: DirectMessageViewModel = .init(with: .init(userId: userId ?? "",
                                                                  sendTrigger: sendTrigger),
                                                      and: disposeBag)
        
        binding(with: viewModel)
        viewModel.load()
        self.viewModel = viewModel
    }
    
    private func binding(with viewModel: DirectMessageViewModel) {
        let output = viewModel.output
        output.messages.bind(to: messages).disposed(by: disposeBag)
        output.sendCompleted.bind(to: sendCompleted).disposed(by: disposeBag)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
}
