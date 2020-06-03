//
//  PollView.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/03.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxCocoa
import RxSwift
import UIKit

class PollView: UIView {
    @IBOutlet weak var stackView: UIStackView!
    @IBOutlet weak var totalPollLabel: UILabel!
    @IBOutlet weak var pollButton: UIButton!
    
    let disposeBag = DisposeBag()
    var voteTriggar: PublishRelay<[Int]> = .init() // タップされるとvote対象のidを流す
    var height: CGFloat { // NoteCellがこれを使ってAutoLayoutを設定する
        guard pollBarCount > 0 else { return 0 }
        
        //        pollBars.forEach { $0.setNeedsLayout(); $0.layoutIfNeeded() }
        //        let sumOfPollHeight = pollBars.map { pollBar in
        //            pollBar.layoutIfNeeded()
        //            return pollBar.frame.height
        //        }.reduce(CGFloat.zero) { x, y in x + y }
        //
        let spaceCount = pollBarCount - 1
        return CGFloat(spaceCount * 10 + pollBarCount * pollBarHeight + 38) + totalPollLabel.frame.height
    }
    
    private var pollBarHeight = 35
    private var pollBarCount = 0
    private var votesCountSum: Float = 0 {
        didSet {
            totalPollLabel.text = "\(Int(votesCountSum))票"
        }
    }
    
    private var pollBars: [PollBar] = []
    private var selectedId: [Int] = []
    private var allowedMultiple: Bool = false // 複数選択可かどうか
    private var finishVoting: Bool = false
    
    // MARK: Life Cycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        loadNib()
        setTheme()
        setupComponent()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
        loadNib()
        setTheme()
        setupComponent()
    }
    
    func loadNib() {
        if let view = UINib(nibName: "PollView", bundle: Bundle(for: type(of: self))).instantiate(withOwner: self, options: nil)[0] as? UIView {
            view.frame = bounds
            view.backgroundColor = .clear
            addSubview(view)
        }
    }
    
    // MARK: Design
    
    private func setTheme() {
        if let colorPattern = Theme.shared.currentModel?.colorPattern.ui {
            backgroundColor = colorPattern.base
            totalPollLabel.textColor = colorPattern.text
        }
        if let mainColorHex = Theme.shared.currentModel?.mainColorHex {
            let mainColor = UIColor(hex: mainColorHex)
            pollButton.setTitleColor(mainColor, for: .normal)
            pollButton.layer.borderColor = mainColor.cgColor
        }
    }
    
    func setupComponent() {
        pollButton.layer.borderWidth = 1
        pollButton.layer.cornerRadius = 5
        pollButton.setTitle("投票", for: .normal)
        pollButton.contentEdgeInsets = .init(top: 5, left: 10, bottom: 5, right: 10)
        
        pollButton.rx.tap.subscribe(onNext: { _ in
            guard self.selectedId.count > 0, !self.finishVoting else { return }
            self.finishVoting = true
            self.updatePoll(tapped: self.selectedId)
            self.disablePollButton()
            self.voteTriggar.accept(self.selectedId)
        }).disposed(by: disposeBag)
    }
    
    // MARK: Publics
    
    func setPoll(with pollModel: Poll) {
        guard let choices = pollModel.choices?.compactMap({ $0 })
        else { isHidden = true; return } // Poll情報が取得できない場合はPollView自体を非表示にする
        
        votesCountSum = choices.map { Float($0.votes ?? 0) }.reduce(0) { x, y in x + y }
        pollBarCount = choices.count
        
        let finishVoting: Bool = choices.map { $0.isVoted ?? false }.reduce(false) { x, y in x || y } // 一度でも自分は投票したか？
        
        for id in 0 ..< choices.count { // 実際にvoteする際に、何番目の選択肢なのかサーバーに送信するのでforで回す
            let choice = choices[id]
            guard let count = choice.votes else { return }
            
            let pollBar = PollBar(frame: CGRect(x: 0, y: 0, width: 300, height: pollBarHeight),
                                  id: id,
                                  name: choice.text ?? "",
                                  voteCount: count,
                                  rate: votesCountSum == 0 ? 0 : Float(count) / votesCountSum,
                                  finishVoting: finishVoting,
                                  myVoted: choice.isVoted ?? false)
            
            pollBar.translatesAutoresizingMaskIntoConstraints = false
            setupPollBarTapGesture(with: pollBar, finishVoting)
            pollBars.append(pollBar)
            stackView.addArrangedSubview(pollBar)
            setAutoLayout(pollBar)
        }
        
        if finishVoting {
            pollButton.setTitle("投票済", for: .normal)
        }
        
        allowedMultiple = pollModel.multiple ?? false
        self.finishVoting = finishVoting
    }
    
    func initialize() {
        pollBars.removeAll()
        selectedId.removeAll()
        stackView.arrangedSubviews.forEach {
            $0.removeFromSuperview()
        }
    }
    
    func changePoll() {}
    
    // MARK: Privates
    
    private func setupPollBarTapGesture(with pollBar: PollBar, _ cannotVote: Bool) {
        guard !cannotVote else { return }
        
        pollBar.setTapGesture(disposeBag, closure: {
            if self.selectedId.count > 0, !self.allowedMultiple { // 選択は一つまでの時
                self.pollBars
                    .filter { self.selectedId.contains($0.id) }
                    .forEach { $0.changeRadioState() } // 既存の選択を解除する
                self.selectedId.removeAll()
            }
            
            pollBar.changeRadioState()
            
            if pollBar.selected {
                self.selectedId.append(pollBar.id)
            } else if self.allowedMultiple { // 選択が解除され且つ複数選択可の場合
                guard let index = self.selectedId.firstIndex(of: pollBar.id) else { return }
                self.selectedId.remove(at: index)
            }
        })
    }
    
    private func setAutoLayout(_ view: PollBar) {
        stackView.addConstraints([
            NSLayoutConstraint(item: view,
                               attribute: .height,
                               relatedBy: .greaterThanOrEqual,
                               toItem: stackView,
                               attribute: .height,
                               multiplier: 0,
                               constant: 35)
        ])
    }
    
    private func updatePoll(tapped ids: [Int]) {
        votesCountSum += Float(ids.count)
        pollBars.forEach { pollBar in // PollViewのタップイベントが発生したら、PollViewの状態をすべて変更する
            let newVoteCount = pollBar.voteCount + (ids.contains(pollBar.id) ? 1 : 0)
            let newRate = Float(newVoteCount) / self.votesCountSum
            
            pollBar.changeState(voted: true, voteCount: newVoteCount, rate: newRate)
        }
    }
    
    private func disablePollButton() {
        UIView.animate(withDuration: 0.9, delay: 0.3, options: .curveEaseInOut, animations: {
            self.pollButton.setTitle("投票済", for: .normal)
        }, completion: nil)
    }
}

// MARK: PollBar

extension PollView {
    class PollBar: UIView {
        struct Style {
            var backgroundColor: UIColor = .clear
            var textColor: UIColor = .black
            var progressColor: UIColor = .systemBlue
            var borderColor: UIColor = .lightGray
            
            var cornerRadius: CGFloat = 5
        }
        
        var id: Int = -1
        var voteCount: Int = 0
        var idOfTapped: Observable<Int>? // PollBarのidを流す
        
        private lazy var style: Style = getStyle()
        private var finishVoting: Bool = false
        
        private var nameLabel: UILabel = .init()
        private var rateLabel: UILabel = .init()
        private var progressView: UIView = .init()
        private var radioButton: RadioButton?
        private var progressConstraint: NSLayoutConstraint?
        private var pollNameConstraint: NSLayoutConstraint?
        
        private let disposeBag = DisposeBag()
        
        var selected: Bool {
            guard let radioButton = radioButton else { return false }
            return radioButton.currentState == .on
        }
        
        // MARK: LifeCycle
        
        init(frame: CGRect, id: Int, name: String, voteCount: Int, rate: Float, finishVoting: Bool, myVoted: Bool, style: Style? = nil) {
            super.init(frame: frame)
            self.frame = frame
            self.style = style ?? self.style
            self.id = id
            self.finishVoting = finishVoting
            self.voteCount = voteCount
            
            let progressView = setupProgressView(rate: rate, canSeeRate: finishVoting, style: self.style)
            let radioButton = setupRadioButton(finishVoting: finishVoting)
            let nameLabel = setupNameLabel(name: name, finishVoting: finishVoting, style: self.style, radioButton: radioButton)
            let rateLabel = setupRateLabel(rate: rate, canSeeRate: finishVoting, style: self.style, nameLabel: nameLabel)
            
            changeStyle(with: self.style)
            
            self.progressView = progressView
            self.radioButton = radioButton
            self.nameLabel = nameLabel
            self.rateLabel = rateLabel
            
            isUserInteractionEnabled = !finishVoting
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        private func getStyle() -> Style {
            let theme = Theme.shared.currentModel
            return .init(backgroundColor: .clear,
                         textColor: theme?.colorPattern.ui.text ?? .black,
                         progressColor: getMainColor(),
                         borderColor: theme?.colorPattern.ui.sub3 ?? .lightGray,
                         cornerRadius: 5)
        }
        
        private func getMainColor() -> UIColor {
            guard let mainColorHex = Theme.shared.currentModel?.mainColorHex else { return .systemBlue }
            return UIColor(hex: mainColorHex)
        }
        
        // MARK: Publics
        
        /// 投票率を変更し、アニメートさせる
        /// - Parameter newRate: 新しい投票率
        func changePollRate(to newRate: Float) {
            rateLabel.text = "\(Int(100 * newRate))%"
            
            // AutoLayoutを再設定
            guard let progressConstraint = progressConstraint,
                let pollNameConstraint = pollNameConstraint else { return }
            
            removeConstraint(progressConstraint)
            removeConstraint(pollNameConstraint)
            
            let newProgressConstraint = NSLayoutConstraint(item: progressView,
                                                           attribute: .width,
                                                           relatedBy: .equal,
                                                           toItem: self,
                                                           attribute: .width,
                                                           multiplier: CGFloat(newRate),
                                                           constant: 0)
            
            let newPollNameConstraint = NSLayoutConstraint(item: nameLabel,
                                                           attribute: .left,
                                                           relatedBy: .equal,
                                                           toItem: self,
                                                           attribute: .left,
                                                           multiplier: 1.0,
                                                           constant: 10)
            
            addConstraint(newProgressConstraint)
            addConstraint(newPollNameConstraint)
            
            self.progressConstraint = newProgressConstraint
            
            UIView.animate(withDuration: 0.5, delay: 0, options: .curveEaseInOut, animations: {
                if !self.finishVoting {
                    self.progressView.alpha = 1
                    self.rateLabel.alpha = 1
                }
                
                self.radioButton?.alpha = 0
                self.layoutIfNeeded() // AutoLayout更新
            }, completion: { _ in
                self.finishVoting = true
            })
        }
        
        /// 投票済みかどうかの状態を変更する
        /// - Parameter voted: 投票済みならtrue
        func changeState(voted: Bool, voteCount: Int, rate: Float) {
            self.voteCount = voteCount
            isUserInteractionEnabled = !voted // 投票されたらタップできないようにする
            if voted {
                changePollRate(to: rate)
            }
        }
        
        // MARK: Privates
        
        // ProgressViewを設定
        private func setupProgressView(rate: Float, canSeeRate: Bool, style: Style) -> UIView {
            let progressView = UIView()
            let frame = self.frame
            
            progressView.backgroundColor = style.progressColor
            progressView.frame = CGRect(x: frame.origin.x,
                                        y: frame.origin.y,
                                        width: frame.width * CGFloat(rate),
                                        height: frame.height)
            
            progressView.layer.cornerRadius = style.cornerRadius
            progressView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(progressView)
            
            // AutoLayout
            let progressConstraint = NSLayoutConstraint(item: progressView,
                                                        attribute: .width,
                                                        relatedBy: .equal,
                                                        toItem: self,
                                                        attribute: .width,
                                                        multiplier: CGFloat(rate),
                                                        constant: 0)
            
            addConstraints([
                progressConstraint,
                NSLayoutConstraint(item: progressView,
                                   attribute: .left,
                                   relatedBy: .equal,
                                   toItem: self,
                                   attribute: .left,
                                   multiplier: 1.0,
                                   constant: 0),
                
                NSLayoutConstraint(item: progressView,
                                   attribute: .centerY,
                                   relatedBy: .equal,
                                   toItem: self,
                                   attribute: .centerY,
                                   multiplier: 1.0,
                                   constant: 0),
                
                NSLayoutConstraint(item: progressView,
                                   attribute: .height,
                                   relatedBy: .equal,
                                   toItem: self,
                                   attribute: .height,
                                   multiplier: 1.0,
                                   constant: 0)
            ])
            
            progressView.alpha = canSeeRate ? 1 : 0 // 表示OKなら表示
            self.progressConstraint = progressConstraint
            
            return progressView
        }
        
        // 選択肢のラベルを設定
        private func setupNameLabel(name: String, finishVoting: Bool, style: Style, radioButton: UIView) -> UILabel {
            let pollNameLabel = UILabel()
            pollNameLabel.numberOfLines = 0
//            pollNameLabel.lineBreakMode = NSLineBreakMode.byWordWrapping
            pollNameLabel.lineBreakMode = .byTruncatingTail
            pollNameLabel.font = UIFont.systemFont(ofSize: 15.0)
            pollNameLabel.text = name
            pollNameLabel.textColor = style.textColor
            pollNameLabel.sizeToFit()
            
            pollNameLabel.center = center
            pollNameLabel.frame = .init(x: 10,
                                        y: pollNameLabel.frame.origin.y,
                                        width: pollNameLabel.frame.width,
                                        height: pollNameLabel.frame.height)
            
            pollNameLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(pollNameLabel)
            
            var pollNameConstraint: NSLayoutConstraint
            if finishVoting {
                pollNameConstraint = NSLayoutConstraint(item: pollNameLabel,
                                                        attribute: .left,
                                                        relatedBy: .equal,
                                                        toItem: self,
                                                        attribute: .left,
                                                        multiplier: 1.0,
                                                        constant: 10)
            } else {
                pollNameConstraint = NSLayoutConstraint(item: pollNameLabel,
                                                        attribute: .left,
                                                        relatedBy: .equal,
                                                        toItem: radioButton,
                                                        attribute: .right,
                                                        multiplier: 1.0,
                                                        constant: 10)
            }
            
            // AutoLayout
            addConstraints([
                pollNameConstraint,
                NSLayoutConstraint(item: pollNameLabel,
                                   attribute: .top,
                                   relatedBy: .equal,
                                   toItem: self,
                                   attribute: .top,
                                   multiplier: 1.0,
                                   constant: 0),
                
                NSLayoutConstraint(item: pollNameLabel,
                                   attribute: .bottom,
                                   relatedBy: .equal,
                                   toItem: self,
                                   attribute: .bottom,
                                   multiplier: 1.0,
                                   constant: 0)
            ])
            
            self.pollNameConstraint = pollNameConstraint
            return pollNameLabel
        }
        
        // 投票率のラベルを設定
        private func setupRateLabel(rate: Float, canSeeRate: Bool, style: Style, nameLabel: UIView) -> UILabel {
            let pollRateLabel = UILabel()
            pollRateLabel.numberOfLines = 0
            pollRateLabel.lineBreakMode = NSLineBreakMode.byWordWrapping
            pollRateLabel.minimumScaleFactor = 5
            pollRateLabel.font = UIFont.systemFont(ofSize: 15.0)
            pollRateLabel.text = "\(Int(100 * rate))%"
            pollRateLabel.textColor = style.textColor
            pollRateLabel.textAlignment = .right
            pollRateLabel.minimumScaleFactor = 0.1
            
            pollRateLabel.alpha = canSeeRate ? 1 : 0 // 表示OKなら表示
            pollRateLabel.center = pollRateLabel.center
            pollRateLabel.sizeToFit()
            pollRateLabel.frame = .init(x: frame.width - pollRateLabel.frame.width - 5,
                                        y: pollRateLabel.frame.origin.y + 5,
                                        width: pollRateLabel.frame.width,
                                        height: pollRateLabel.frame.height)
            
            pollRateLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(pollRateLabel)
            
            // AutoLayout
            addConstraints([
                NSLayoutConstraint(item: pollRateLabel,
                                   attribute: .left,
                                   relatedBy: .equal,
                                   toItem: nameLabel,
                                   attribute: .right,
                                   multiplier: 1.0,
                                   constant: 5),
                NSLayoutConstraint(item: pollRateLabel,
                                   attribute: .right,
                                   relatedBy: .equal,
                                   toItem: self,
                                   attribute: .right,
                                   multiplier: 1.0,
                                   constant: -10),
                
                NSLayoutConstraint(item: pollRateLabel,
                                   attribute: .width,
                                   relatedBy: .equal,
                                   toItem: self,
                                   attribute: .width,
                                   multiplier: 0,
                                   constant: 40),
                
                NSLayoutConstraint(item: pollRateLabel,
                                   attribute: .centerY,
                                   relatedBy: .equal,
                                   toItem: self,
                                   attribute: .centerY,
                                   multiplier: 1.0,
                                   constant: 0)
            ])
            return pollRateLabel
        }
        
        private func setupRadioButton(finishVoting: Bool) -> RadioButton {
            // color
            let theme = Theme.shared.currentModel
            
            let radio = RadioButton(frame: .zero,
                                    normalColor: theme?.colorPattern.ui.sub2 ?? .black,
                                    selectedColor: theme?.colorPattern.ui.sub2 ?? .black) // getMainColor())
            radio.layer.borderColor = theme?.colorPattern.ui.sub2.cgColor ?? UIColor.lightGray.cgColor
            
            // autolayout
            radio.translatesAutoresizingMaskIntoConstraints = false
            addSubview(radio)
            addConstraints([
                NSLayoutConstraint(item: radio,
                                   attribute: .left,
                                   relatedBy: .equal,
                                   toItem: self,
                                   attribute: .left,
                                   multiplier: 1.0,
                                   constant: 10),
                
                NSLayoutConstraint(item: radio,
                                   attribute: .centerY,
                                   relatedBy: .equal,
                                   toItem: self,
                                   attribute: .centerY,
                                   multiplier: 1.0,
                                   constant: 0),
                
                NSLayoutConstraint(item: radio,
                                   attribute: .width,
                                   relatedBy: .equal,
                                   toItem: radio,
                                   attribute: .height,
                                   multiplier: 1.0,
                                   constant: 0),
                
                NSLayoutConstraint(item: radio,
                                   attribute: .height,
                                   relatedBy: .equal,
                                   toItem: self,
                                   attribute: .height,
                                   multiplier: 0,
                                   constant: 24.5)
            ])
            
            radio.alpha = finishVoting ? 0 : 1
            return radio
        }
        
        // PollBarのデザインを変更
        private func changeStyle(with style: Style) {
            backgroundColor = style.backgroundColor
            layer.cornerRadius = style.cornerRadius
            layer.borderWidth = 1
            layer.borderColor = style.borderColor.cgColor
            nameLabel.textColor = style.textColor
            rateLabel.textColor = style.textColor
        }
        
        // 未投票時は見えなくなっているものを見えるようにする
        private func visualizePoll() {
            UIView.animate(withDuration: 0.5, delay: 0, options: .curveEaseInOut, animations: {
                self.progressView.alpha = 1
                self.rateLabel.alpha = 1
                
            }, completion: { _ in
                self.finishVoting = true
            })
        }
        
        func changeRadioState() {
            guard let radioButton = radioButton else { return }
            let state: RadioButton.RadioState = radioButton.currentState == .on ? .off : .on
            
            radioButton.change(state: state)
        }
    }
}

class RadioButton: UIView {
    enum RadioState {
        case on
        case off
    }
    
    var currentState: RadioState = .off
    
    private var normalColor: UIColor = .black
    private var selectedColor: UIColor = .systemBlue
    private var innerView: UIView = .init()
    
    init(frame: CGRect, normalColor: UIColor, selectedColor: UIColor) {
        self.normalColor = normalColor
        self.selectedColor = selectedColor
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = frame.width / 2
        innerView.layer.cornerRadius = innerView.frame.width / 2
    }
    
    private func setup() {
        backgroundColor = .clear
        layer.borderColor = normalColor.cgColor
        layer.borderWidth = 1
        clipsToBounds = true
        
        // innerView
        innerView.translatesAutoresizingMaskIntoConstraints = false
        innerView.clipsToBounds = true
        innerView.backgroundColor = selectedColor
        innerView.alpha = 0
        addSubview(innerView)
        addConstraints([
            NSLayoutConstraint(item: innerView,
                               attribute: .centerX,
                               relatedBy: .equal,
                               toItem: self,
                               attribute: .centerX,
                               multiplier: 1.0,
                               constant: 0),
            
            NSLayoutConstraint(item: innerView,
                               attribute: .centerY,
                               relatedBy: .equal,
                               toItem: self,
                               attribute: .centerY,
                               multiplier: 1.0,
                               constant: 0),
            
            NSLayoutConstraint(item: innerView,
                               attribute: .width,
                               relatedBy: .equal,
                               toItem: innerView,
                               attribute: .height,
                               multiplier: 1.0,
                               constant: 0),
            
            NSLayoutConstraint(item: innerView,
                               attribute: .height,
                               relatedBy: .equal,
                               toItem: self,
                               attribute: .height,
                               multiplier: 0.55,
                               constant: 0)
        ])
    }
    
    func change(state: RadioState) {
        guard state != currentState else { return }
        
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut, animations: {
            self.innerView.layer.cornerRadius = self.innerView.frame.width / 2
            self.innerView.alpha = state == .on ? 1 : 0
        }, completion: nil)
        
        currentState = state
    }
}
