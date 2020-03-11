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

public class PollView: UIView {
    @IBOutlet weak var stackView: UIStackView!
    @IBOutlet weak var totalPollLabel: UILabel!
    
    public var voteTriggar: Observable<Int>? // タップされるとvote対象のidを流す
    public var height: CGFloat {
        guard pollBarCount > 0 else { return 0 }
        
        let spaceCount = pollBarCount - 1
        return CGFloat(spaceCount * 10 + pollBarCount * pollBarHeight + 38) + totalPollLabel.frame.height
    }
    
    private var pollBarHeight = 30
    private var pollBarCount = 0 {
        didSet {
            totalPollLabel.text = "計 \(pollBarCount)票"
        }
    }
    
    private var votesCountSum: Float = 0
    private var pollBars: [PollBar] = []
    private let disposeBag = DisposeBag()
    
    // MARK: Life Cycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        loadNib()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
        loadNib()
    }
    
    public func loadNib() {
        if let view = UINib(nibName: "PollView", bundle: Bundle(for: type(of: self))).instantiate(withOwner: self, options: nil)[0] as? UIView {
            view.frame = bounds
            addSubview(view)
        }
    }
    
    // MARK: Publics
    
    public func setPoll(with pollModel: Poll) {
        guard let choices = pollModel.choices?.compactMap({ $0 })
        else { isHidden = true; return } // Poll情報が取得できない場合はPollView自体を非表示にする
        
        votesCountSum = choices.map { Float($0.votes ?? 0) }.reduce(0) { x, y in x + y }
        pollBarCount = choices.count
        
        let canSeeRate: Bool = choices.map { $0.isVoted ?? false }.reduce(false) { x, y in x || y } // 一度でも自分は投票したか？
        
        for id in 0 ..< choices.count { // 実際にvoteする際に、何番目の選択肢なのかサーバーに送信するのでforで回す
            let choice = choices[id]
            guard let count = choice.votes else { return }
            
            let pollBar = PollBar(frame: CGRect(x: 0, y: 0, width: 300, height: pollBarHeight),
                                  id: id,
                                  name: choice.text ?? "",
                                  voteCount: count,
                                  rate: votesCountSum == 0 ? 0 : Float(count) / votesCountSum,
                                  canSeeRate: canSeeRate,
                                  isVoted: choice.isVoted ?? false)
            
            setupPollBarTapGesture(with: pollBar)
            pollBars.append(pollBar)
            stackView.addArrangedSubview(pollBar)
        }
    }
    
    public func initialize() {
        pollBars.removeAll()
        stackView.arrangedSubviews.forEach {
            $0.removeFromSuperview()
        }
    }
    
    public func changePoll() {}
    
    // MARK: Privates
    
    private func setupPollBarTapGesture(with pollBar: PollBar) {
        guard let idOfTapped = pollBar.idOfTapped else { return }
        
        // PollViewのイベントをすべてmerge
        voteTriggar = voteTriggar == nil ? idOfTapped : Observable.of(voteTriggar!, idOfTapped).merge()
        voteTriggar!.subscribe(onNext: { id in
            self.votesCountSum += 1
            self.pollBars.forEach { pollBar in // PollViewのタップイベントが発生したら、PollViewの状態をすべて変更する
                let newVoteCount = pollBar.voteCount + (pollBar.id == id ? 1 : 0)
                let newRate = Float(newVoteCount) / self.votesCountSum
                
                pollBar.changeState(voted: true, voteCount: newVoteCount, rate: newRate)
            }
        }).disposed(by: disposeBag)
    }
}

// MARK: PollBar

extension PollView {
    public class PollBar: UIView {
        public struct Style {
            var backgroundColor: UIColor = .init(hex: "ebebeb")
            var textColor: UIColor = .black
            var progressColor: UIColor = .systemBlue
            
            var cornerRadius: CGFloat = 8
        }
        
        public var id: Int = -1
        public var voteCount: Int = 0
        public var idOfTapped: Observable<Int>? // PollBarのidを流す
        
        private var style: Style = .init()
        private var canSeeRate: Bool = false
        
        private var nameLabel: UILabel = .init()
        private var rateLabel: UILabel = .init()
        private var progressView: UIView = .init()
        
        private let disposeBag = DisposeBag()
        
        // MARK: LifeCycle
        
        init(frame: CGRect, id: Int, name: String, voteCount: Int, rate: Float, canSeeRate: Bool, isVoted: Bool, style: Style = .init()) {
            super.init(frame: frame)
            self.frame = frame
            self.style = style
            self.id = id
            self.canSeeRate = canSeeRate
            self.voteCount = voteCount
            
            progressView = setupProgressView(rate: rate, canSeeRate: canSeeRate, style: style)
            nameLabel = setupNameLabel(name: name, isVoted: isVoted, style: style)
            rateLabel = setupRateLabel(rate: rate, canSeeRate: canSeeRate, style: style)
            
            changeStyle(with: style)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        // MARK: Publics
        
        /// 投票率を変更し、アニメートさせる
        /// - Parameter newRate: 新しい投票率
        public func changePollRate(to newRate: Float) {
            let frame = self.frame
            rateLabel.text = "\(Int(100 * newRate))%"
            UIView.animate(withDuration: 0.5, delay: 0, options: .curveEaseInOut, animations: {
                if !self.canSeeRate {
                    self.progressView.alpha = 1
                    self.rateLabel.alpha = 1
                }
                self.progressView.frame = CGRect(x: self.progressView.frame.origin.x,
                                                 y: self.progressView.frame.origin.y,
                                                 width: frame.width * CGFloat(newRate),
                                                 height: self.progressView.frame.height)
            }, completion: { _ in
                self.canSeeRate = true
            })
        }
        
        /// 投票済みかどうかの状態を変更する
        /// - Parameter voted: 投票済みならtrue
        public func changeState(voted: Bool, voteCount: Int, rate: Float) {
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
            addSubview(progressView)
            
            setVoteGesture()
            
            progressView.alpha = canSeeRate ? 1 : 0 // 表示OKなら表示
            return progressView
        }
        
        // 選択肢のラベルを設定
        private func setupNameLabel(name: String, isVoted: Bool, style: Style) -> UILabel {
            let pollNameLabel = UILabel()
            pollNameLabel.numberOfLines = 0
            pollNameLabel.lineBreakMode = NSLineBreakMode.byWordWrapping
            pollNameLabel.font = UIFont.systemFont(ofSize: 15.0)
            pollNameLabel.text = (isVoted ? "✔ " : "") + name
            pollNameLabel.textColor = style.textColor
            pollNameLabel.sizeToFit()
            
            pollNameLabel.center = center
            pollNameLabel.frame = .init(x: 10,
                                        y: pollNameLabel.frame.origin.y,
                                        width: pollNameLabel.frame.width,
                                        height: pollNameLabel.frame.height)
            
            pollNameLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(pollNameLabel)
            
            // AutoLayout
            addConstraints([
                NSLayoutConstraint(item: pollNameLabel,
                                   attribute: .left,
                                   relatedBy: .equal,
                                   toItem: self,
                                   attribute: .left,
                                   multiplier: 1.0,
                                   constant: 10),
                
                NSLayoutConstraint(item: pollNameLabel,
                                   attribute: .centerY,
                                   relatedBy: .equal,
                                   toItem: self,
                                   attribute: .centerY,
                                   multiplier: 1.0,
                                   constant: 0)
            ])
            
            return pollNameLabel
        }
        
        // 投票率のラベルを設定
        private func setupRateLabel(rate: Float, canSeeRate: Bool, style: Style) -> UILabel {
            let pollRateLabel = UILabel()
            pollRateLabel.numberOfLines = 0
            pollRateLabel.lineBreakMode = NSLineBreakMode.byWordWrapping
            pollRateLabel.minimumScaleFactor = 5
            pollRateLabel.font = UIFont.systemFont(ofSize: 15.0)
            pollRateLabel.text = "\(Int(100 * rate))%"
            pollRateLabel.textColor = style.textColor
            
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
                                   attribute: .right,
                                   relatedBy: .equal,
                                   toItem: self,
                                   attribute: .right,
                                   multiplier: 1.0,
                                   constant: -10),
                
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
        
        // PollBarのデザインを変更
        private func changeStyle(with style: Style) {
            backgroundColor = style.backgroundColor
            layer.cornerRadius = style.cornerRadius
        }
        
        // Voteジェスチャー(タップジェスチャー)を設定
        private func setVoteGesture() {
            let tapGesture = UITapGestureRecognizer()
            idOfTapped = tapGesture.rx.event.map { _ in self.id }
            
            isUserInteractionEnabled = !canSeeRate
            addGestureRecognizer(tapGesture)
            setupVisualizePollTrigger(with: tapGesture.rx.event.asObservable())
        }
        
        // 使用者が投票したら、投票率と投票数を表示する
        private func setupVisualizePollTrigger(with observable: Observable<UITapGestureRecognizer>) {
            observable.subscribe(onNext: { _ in
                guard !self.canSeeRate else { return }
                self.visualizePoll()
            }).disposed(by: disposeBag)
        }
        
        // 未投票時は見えなくなっているものを見えるようにする
        private func visualizePoll() {
            UIView.animate(withDuration: 0.5, delay: 0, options: .curveEaseInOut, animations: {
                self.progressView.alpha = 1
                self.rateLabel.alpha = 1
                
            }, completion: { _ in
                self.canSeeRate = true
            })
        }
    }
}
