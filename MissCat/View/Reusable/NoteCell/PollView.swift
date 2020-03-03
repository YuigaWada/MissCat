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
        
        let originalFrame = frame
        let spaceCount = pollBarCount - 1
        return CGFloat(spaceCount * 10 + pollBarCount * 20 + 20 + 100)
    }
    
    private var pollBarHeight = 20
    private var pollBarCount = 0
    
    private var votesCountSum: Int = 0
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
            
            let pollBar = getPollBarView(name: "a",
                                         rate: 0.7,
                                         isVoted: false)
            
            stackView.addArrangedSubview(pollBar.view)
        }
    }
    
    // MARK: Publics
    
    public func setPoll(with pollModel: Poll) {
        guard let choices = pollModel.choices?.compactMap({ $0 })
        else { isHidden = true; return } // Poll情報が取得できない場合はPollView自体を非表示にする
        
        votesCountSum = choices.map { $0.votes ?? 0 }.reduce(0) { x, y in x + y }
        pollBarCount = choices.count
        
        choices.forEach { choice in
            guard let count = choice.votes else { return }
            
            let pollBar = getPollBarView(name: choice.text ?? "",
                                         rate: votesCountSum == 0 ? 0 : Double(count / votesCountSum),
                                         isVoted: choice.isVoted ?? false)
            
            pollBars.append(pollBar)
            self.stackView.addArrangedSubview(pollBar.view)
        }
    }
    
    public func changePoll() {}
    
    // MARK: Privates
    
    private func getPollBarView(name: String, rate: Double, isVoted: Bool) -> PollBar {
        // プログレスバー
        let pollBarView = UIProgressView(frame: CGRect(x: 0,
                                                       y: 0,
                                                       width: Int(frame.width),
                                                       height: pollBarHeight))
        
        pollBarView.transform = CGAffineTransform(scaleX: 1.0, y: 6.0)
        pollBarView.progressTintColor = .blue
        pollBarView.setProgress(0, animated: true)
        
        // 選択肢のラベル
        let pollNameLabel = UILabel()
        pollNameLabel.numberOfLines = 0
        pollNameLabel.lineBreakMode = NSLineBreakMode.byWordWrapping
        pollNameLabel.font = UIFont.systemFont(ofSize: 15.0)
        pollNameLabel.text = name
        pollNameLabel.center = pollBarView.center
        pollNameLabel.frame = .init(x: 10,
                                    y: pollNameLabel.frame.origin.y,
                                    width: pollNameLabel.frame.width,
                                    height: pollNameLabel.frame.height)
        
        // パーセンテージのラベル
        let pollRateLabel = UILabel()
        pollRateLabel.numberOfLines = 0
        pollRateLabel.lineBreakMode = NSLineBreakMode.byWordWrapping
        pollRateLabel.font = UIFont.systemFont(ofSize: 15.0)
        pollRateLabel.text = String(100 * rate) + "％"
        pollRateLabel.center = pollRateLabel.center
        pollRateLabel.frame = .init(x: frame.width - pollRateLabel.frame.width - 10,
                                    y: pollRateLabel.frame.origin.y,
                                    width: pollRateLabel.frame.width,
                                    height: pollRateLabel.frame.height)
        
        return PollBar(view: pollBarView,
                       nameLabel: pollNameLabel,
                       rateLabel: pollRateLabel)
    }
}

extension PollView {
    public struct PollBar {
        var id: String = UUID().uuidString
        
        let view: UIProgressView
        let nameLabel: UILabel
        let rateLabel: UILabel
        
        public func changePollRate(to newRate: Float) {
            view.setProgress(newRate, animated: true)
            rateLabel.text = String(Int(newRate)) + "％"
        }
    }
}
