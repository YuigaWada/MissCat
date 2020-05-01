//
//  SenderCell.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/16.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxCocoa
import RxDataSources
import RxSwift
import UIKit

class SenderCell: UITableViewCell, ComponentType {
    typealias Transformed = SenderCell
    typealias Arg = SenderCell.Model
    
    @IBOutlet weak var iconImage: UIImageView!
    @IBOutlet weak var nameTextView: MisskeyTextView!
    @IBOutlet weak var messageTextView: MisskeyTextView!
    @IBOutlet weak var agoLabel: UILabel!
    
    private var isSkelton: Bool = false
    private var initialized: Bool = false
    
    override func layoutSubviews() {
        iconImage.layer.cornerRadius = iconImage.frame.width / 2
        nameTextView.transformText()
        
        guard !initialized else { return }
        setTheme()
        initialized = true
    }
    
    // MARK: Design
    
    private func setTheme() {
        if let colorPattern = Theme.shared.currentModel?.colorPattern.ui {
            backgroundColor = colorPattern.base
            messageTextView.textColor = colorPattern.text
        }
    }
    
    // MARK: Publics
    
    func transform(isSkelton: Bool = false) -> SenderCell {
        self.isSkelton = isSkelton
        return self
    }
    
    func transform(with arg: SenderCell.Arg) -> SenderCell {
        messageTextView.attributedText = MFMEngine.generatePlaneString(string: arg.latestMessage ?? "",
                                                                       font: UIFont(name: "Helvetica", size: 11.0))
        nameTextView.attributedText = arg.shapedName?.attributed
        agoLabel.text = arg.createdAt?.calculateAgo()
        
        arg.icon?.toUIImage {
            guard let image = $0 else { return }
            DispatchQueue.main.async {
                self.iconImage.image = image
            }
        }
        
        arg.shapedName?.mfmEngine.renderCustomEmojis(on: nameTextView)
        nameTextView.renderViewStrings()
        
        return self
    }
}

extension SenderCell {
    class Model: IdentifiableType, Equatable {
        typealias Identity = String
        let identity: String = String(Float.random(in: 1 ..< 100))
        
        let isSkelton: Bool
        
        let userId: String?
        let icon: String?
        let name: String?
        let username: String?
        let latestMessage: String?
        let createdAt: String?
        
        var shapedName: MFMString?
        init(isSkelton: Bool, userId: String?, icon: String?, name: String?, username: String?, latestMessage: String?, shapedName: MFMString? = nil, createdAt: String?) {
            self.isSkelton = isSkelton
            self.userId = userId
            self.icon = icon
            self.name = name
            self.username = username
            self.latestMessage = latestMessage
            self.shapedName = shapedName
            self.createdAt = createdAt
        }
        
        static func == (lhs: SenderCell.Model, rhs: SenderCell.Model) -> Bool {
            return lhs.identity == rhs.identity
        }
        
        static func fakeSkeltonCell() -> SenderCell.Model {
            return .init(isSkelton: true,
                         userId: nil,
                         icon: nil,
                         name: nil,
                         username: nil,
                         latestMessage: nil,
                         createdAt: nil)
        }
    }
    
    struct Section {
        var items: [Model]
    }
}

extension SenderCell.Section: AnimatableSectionModelType {
    typealias Item = SenderCell.Model
    typealias Identity = String
    
    var identity: String {
        return ""
    }
    
    init(original: SenderCell.Section, items: [SenderCell.Model]) {
        self = original
        self.items = items
    }
}
