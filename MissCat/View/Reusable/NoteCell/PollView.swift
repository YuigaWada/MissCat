//
//  PollView.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/03.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import UIKit

public class PollView: UIView {
    @IBOutlet weak var stackView: UIStackView!
    @IBOutlet weak var totalPollLabel: UILabel!
    
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
        choices.forEach { choice in
            guard let count = choice.votes else { return }
            
            let pollBar = PollBar(frame: CGRect(x: 0, y: 0, width: 300, height: pollBarHeight),
                                  name: choice.text ?? "",
                                  rate: votesCountSum == 0 ? 0 : Float(count) / votesCountSum,
                                  canSeeRate: canSeeRate,
                                  isVoted: choice.isVoted ?? false)
            
            pollBars.append(pollBar)
            self.stackView.addArrangedSubview(pollBar)
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
}

extension PollView {
    public class PollBar: UIView {
        public struct Style {
            var backgroundColor: UIColor = .init(hex: "d3d3d3")
            var textColor: UIColor = .black
            var progressColor: UIColor = .systemBlue
            
            var cornerRadius: CGFloat = 8
        }
        
        public var id: String = UUID().uuidString
        private var style: Style = .init()
        
        private var nameLabel: UILabel = .init()
        private var rateLabel: UILabel = .init()
        private var progressView: UIView = .init()
        
        init(frame: CGRect, name: String, rate: Float, canSeeRate: Bool, isVoted: Bool, style: Style = .init()) {
            super.init(frame: frame)
            self.frame = frame
            self.style = style
            
            progressView = setupProgressView(rate: rate, style: style)
            nameLabel = setupNameLabel(name: name, isVoted: isVoted, style: style)
            rateLabel = setupRateLabel(rate: rate, canSeeRate: canSeeRate, style: style)
            
            changeStyle(with: style)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        private func setupProgressView(rate: Float, style: Style) -> UIView {
            let progressView = UIView()
            let frame = self.frame
            
            progressView.backgroundColor = style.progressColor
            progressView.frame = CGRect(x: frame.origin.x,
                                        y: frame.origin.y,
                                        width: frame.width * CGFloat(rate),
                                        height: frame.height)
            
            progressView.layer.cornerRadius = style.cornerRadius
            addSubview(progressView)
            return progressView
        }
        
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
            
            addSubview(pollNameLabel)
            return pollNameLabel
        }
        
        private func setupRateLabel(rate: Float, canSeeRate: Bool, style: Style) -> UILabel {
            let pollRateLabel = UILabel()
            pollRateLabel.numberOfLines = 0
            pollRateLabel.lineBreakMode = NSLineBreakMode.byWordWrapping
            pollRateLabel.font = UIFont.systemFont(ofSize: 15.0)
            pollRateLabel.text = String(Int(100 * rate)) + "%"
            pollRateLabel.textColor = style.textColor
            
            pollRateLabel.isHidden = !canSeeRate // 表示OKなら表示
            pollRateLabel.center = pollRateLabel.center
            pollRateLabel.sizeToFit()
            pollRateLabel.frame = .init(x: frame.width - pollRateLabel.frame.width - 5,
                                        y: pollRateLabel.frame.origin.y + 3,
                                        width: pollRateLabel.frame.width,
                                        height: pollRateLabel.frame.height)
            
            addSubview(pollRateLabel)
            return pollRateLabel
        }
        
        private func changeStyle(with style: Style) {
            backgroundColor = style.backgroundColor
            layer.cornerRadius = style.cornerRadius
        }
        
        public func changePollRate(to newRate: Float) {
            progressView.frame = CGRect(x: frame.origin.x,
                                        y: frame.origin.y,
                                        width: frame.width * CGFloat(newRate),
                                        height: frame.height)
            rateLabel.text = String(Int(newRate)) + "％"
        }
    }
}
