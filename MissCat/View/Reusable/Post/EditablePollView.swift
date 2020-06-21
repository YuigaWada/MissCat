//
//  EditablePollView.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/05/25.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxCocoa
import RxSwift
import UIKit

class EditablePollView: PollView {
    private var pollBarHeight = 35
    private var pollBars: [EditablePollBar] = []
    
    override var height: CGFloat {
        return CGFloat(pollBars.count * (10 + pollBarHeight) - 10 + 38) + totalPollLabel.frame.height
    }
    
    override func setupComponent() {
        pollButton.setTitle("追加", for: .normal)
        layer.borderWidth = 1
        setupPollBar()
    }
    
    private func setupPollBar() {
        for _ in 0 ..< 2 {
            addPollBar()
        }
    }
    
    private func addPollBar() {
        let pollBar = EditablePollBar()
        let output = pollBar.getOutput()
        
        pollBar.layer.cornerRadius = 5
        pollBar.frame = .init(x: 0, y: 0, width: 0, height: pollBarHeight)
        
        pollBars.append(pollBar)
        setupTrigger(for: output)
        
        stackView.addArrangedSubview(pollBar)
    }
    
    private func setupTrigger(for output: EditablePollBar.Output) {
        output.removeTrigger.subscribe(onNext: { removeTarget in
            self.stackView.removeArrangedSubview(removeTarget)
        }).disposed(by: disposeBag)
    }
}

extension EditablePollView {
    class EditablePollBar: UIView {
        var id: String = UUID().uuidString
        struct Output {
            let rxTextFiled: ControlProperty<String?>
            let removeTrigger: Observable<EditablePollBar> // arg: self
        }
        
        private var textField: UITextField = .init()
        private var removeButton: UIButton = .init()
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            setup()
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func layoutSubviews() {
            super.layoutSubviews()
            removeButton.layer.cornerRadius = removeButton.frame.width / 2
        }
        
        func getOutput() -> Output {
            return .init(rxTextFiled: textField.rx.text,
                         removeTrigger: removeButton.rx.tap.asObservable().map { self })
        }
        
        private func setup() {
            let textField = setupTextFiled()
            let removeButton = setupRemoveButton(textField: textField)
            
            self.textField = textField
            self.removeButton = removeButton
            
            setTheme()
        }
        
        private func setTheme() {
            guard let theme = Theme.shared.currentModel?.colorPattern.ui else { return }
            
            backgroundColor = theme.base
            textField.textColor = theme.text
            removeButton.setTitleColor(theme.sub2, for: .normal)
        }
        
        private func setupTextFiled() -> UITextField {
            let textField: UITextField = .init()
            textField.backgroundColor = .clear
            textField.translatesAutoresizingMaskIntoConstraints = false
            addSubview(textField)
            
            addConstraints([
                NSLayoutConstraint(item: textField,
                                   attribute: .left,
                                   relatedBy: .equal,
                                   toItem: self,
                                   attribute: .left,
                                   multiplier: 1.0,
                                   constant: 10),
                
                NSLayoutConstraint(item: textField,
                                   attribute: .centerY,
                                   relatedBy: .equal,
                                   toItem: self,
                                   attribute: .centerY,
                                   multiplier: 1.0,
                                   constant: 0),
                
                NSLayoutConstraint(item: textField,
                                   attribute: .height,
                                   relatedBy: .equal,
                                   toItem: self,
                                   attribute: .height,
                                   multiplier: 0.7,
                                   constant: 0)
            ])
            
            return textField
        }
        
        private func setupRemoveButton(textField: UIView) -> UIButton {
            let removeButton: UIButton = .init()
            
            removeButton.backgroundColor = .clear
            removeButton.setTitle("trash-alt", for: .normal)
            removeButton.titleLabel?.font = .awesomeRegular(fontSize: 13.0)
            removeButton.translatesAutoresizingMaskIntoConstraints = false
            addSubview(removeButton)
            
            addConstraints([
                NSLayoutConstraint(item: removeButton,
                                   attribute: .right,
                                   relatedBy: .equal,
                                   toItem: self,
                                   attribute: .right,
                                   multiplier: 1.0,
                                   constant: -10),
                
                NSLayoutConstraint(item: removeButton,
                                   attribute: .left,
                                   relatedBy: .equal,
                                   toItem: textField,
                                   attribute: .right,
                                   multiplier: 1.0,
                                   constant: 10),
                
                NSLayoutConstraint(item: removeButton,
                                   attribute: .centerY,
                                   relatedBy: .equal,
                                   toItem: self,
                                   attribute: .centerY,
                                   multiplier: 1.0,
                                   constant: 0),
                
                NSLayoutConstraint(item: removeButton,
                                   attribute: .height,
                                   relatedBy: .equal,
                                   toItem: self,
                                   attribute: .height,
                                   multiplier: 0.7,
                                   constant: 0),
                
                NSLayoutConstraint(item: removeButton,
                                   attribute: .height,
                                   relatedBy: .equal,
                                   toItem: removeButton,
                                   attribute: .width,
                                   multiplier: 1.0,
                                   constant: 0)
            ])
            return removeButton
        }
    }
}
