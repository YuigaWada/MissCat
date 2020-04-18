//
//  DirectMessageViewModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/16.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxCocoa
import RxSwift
import SwiftLinkPreview

class DirectMessageViewModel: ViewModelType {
    // MARK: I/O
    
    struct Input {
        var userId: String
        var sendTrigger: PublishRelay<String>
    }
    
    struct Output {
        let messages: PublishRelay<[DirectMessage]> = .init()
        let sendCompleted: PublishRelay<Bool> = .init()
    }
    
    struct State {}
    
    private let input: Input
    let output: Output = .init()
    
    private var messages: [DirectMessage] = []
    private let model: DirectMessageModel = .init()
    
    private let disposeBag: DisposeBag
    
    // MARK: LifeCycle
    
    init(with input: Input, and disposeBag: DisposeBag) {
        self.input = input
        self.disposeBag = disposeBag
        binding(with: input)
    }
    
    private func binding(with input: Input) {
        input.sendTrigger.subscribe(onNext: { message in
            self.send(message)
        }).disposed(by: disposeBag)
    }
    
    func load(completion: (() -> Void)? = nil) {
        let untilId = messages.count > 0 ? messages[0].messageId : nil
        let option: DirectMessageModel.LoadOption = .init(userId: input.userId, untilId: untilId)
        
        model.load(with: option).subscribe(onNext: { loaded in
            self.messages.insert(loaded, at: 0)
        }, onCompleted: {
            self.output.messages.accept(self.messages)
            completion?()
        }).disposed(by: disposeBag)
    }
    
    func send(_ text: String) {
        model.send(to: input.userId, with: text).subscribe(onNext: { sent in
            self.messages.append(sent)
        }, onCompleted: {
            self.output.sendCompleted.accept(true)
            self.output.messages.accept(self.messages)
        }).disposed(by: disposeBag)
    }
}
