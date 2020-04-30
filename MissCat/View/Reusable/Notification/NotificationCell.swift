//
//  NotificationCell.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/24.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxCocoa
import RxDataSources
import RxSwift
import UIKit

class NotificationCell: UITableViewCell, UITextViewDelegate {
    @IBOutlet weak var iconImageView: UIImageView!
    
    @IBOutlet weak var nameTextView: MisskeyTextView!
    
    @IBOutlet weak var agoLabel: UILabel!
    @IBOutlet weak var noteView: MisskeyTextView!
    
    @IBOutlet weak var followButton: UIButton! // APIがフォロー済みかどうかの情報をワタシてくれないので一時的に「くわしくボタン」へ変更
    @IBOutlet weak var typeIconView: UILabel!
    @IBOutlet weak var typeLabel: UILabel!
    @IBOutlet weak var defaultNoteBottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var separatorView: UIView!
    
    var delegate: NoteCellDelegate?
    
    private var viewModel: NotificationCellViewModel?
    private lazy var emojiView = self.generateEmojiView()
    
    private var emojiViewOnView: Bool = false
    private var disposeBag = DisposeBag()
    private var imageSessionTasks: [URLSessionDataTask] = []
    private var mainColor: UIColor = .systemBlue
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        bindTheme()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        bindTheme()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        setTheme()
        setupComponents()
        nameTextView.transformText()
        
        // MEMO: MisskeyApiの "i/notifications"はfromUserの自己紹介を流してくれないので、対応するまで非表示にする
        //        noteView.transformText()
    }
    
    private func setupComponents() {
        iconImageView.layer.cornerRadius = iconImageView.frame.height / 2
        noteView.delegate = self
        noteView.textColor = .lightGray
        
        typeIconView.font = .awesomeSolid(fontSize: 14.0)
        
        guard !emojiViewOnView else { return }
        addSubview(emojiView)
        emojiViewOnView = true
    }
    
    private func bindTheme() {
        let theme = Theme.shared.theme
        
        theme.map { UIColor(hex: $0.mainColorHex) }.subscribe(onNext: { color in
            self.followButton.backgroundColor = color
        }).disposed(by: disposeBag)
    }
    
    private func setTheme() {
        if let mainColorHex = Theme.shared.currentModel?.mainColorHex {
            mainColor = UIColor(hex: mainColorHex)
        }
        if let colorPattern = Theme.shared.currentModel?.colorPattern.ui {
            backgroundColor = colorPattern.base
            typeLabel.textColor = colorPattern.text
            separatorView.backgroundColor = colorPattern.sub2
        }
    }
    
    func initialize() {
        iconImageView.image = nil
        agoLabel.text = nil
        noteView.attributedText = nil
        typeIconView.text = nil
        typeLabel.text = nil
        
        nameTextView.attributedText = nil
        nameTextView.resetViewString()
        
        emojiView.isHidden = false
        emojiView.initialize()
        
        followButton.isHidden = true
        viewModel?.prepareForReuse()
    }
    
    private func getViewModel(with item: NotificationCell.Model) -> NotificationCellViewModel {
        let input: NotificationCellViewModel.Input = .init(item: item)
        let viewModel = NotificationCellViewModel(with: input, and: disposeBag)
        
        binding(with: viewModel)
        return viewModel
    }
    
    private func binding(with viewModel: NotificationCellViewModel) {
        let output = viewModel.output
        
        // meta
        output.name
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: { nameMfmString in
                self.nameTextView.attributedText = nameMfmString.attributed
                nameMfmString.mfmEngine.renderCustomEmojis(on: self.nameTextView)
            }).disposed(by: disposeBag)
        
        output.note
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: { noteMfmString in
                self.noteView.attributedText = noteMfmString.attributed
                noteMfmString.mfmEngine.renderCustomEmojis(on: self.noteView)
            }).disposed(by: disposeBag)
        
        output.iconImage
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(iconImageView.rx.image)
            .disposed(by: disposeBag)
        
        output.ago
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(agoLabel.rx.text)
            .disposed(by: disposeBag)
        
        // color
        output.mainColor
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(followButton.rx.backgroundColor)
            .disposed(by: disposeBag)
        
        output.textColor
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: { self.followButton.setTitleColor($0, for: .normal) })
            .disposed(by: disposeBag)
        
        output.textColor
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: { self.typeLabel.textColor = $0 })
            .disposed(by: disposeBag)
        
        output.backgroundColor
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(rx.backgroundColor)
            .disposed(by: disposeBag)
        
        // emoji
        output.needEmoji
            .map { !$0 }
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(emojiView.rx.isHidden)
            .disposed(by: disposeBag)
        
        output.emoji
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: { self.emojiView.emoji = $0 })
            .disposed(by: disposeBag)
        
        // response
        output.typeString
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(typeLabel.rx.text)
            .disposed(by: disposeBag)
        
        output.typeIconColor
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: { self.typeIconView.textColor = $0 })
            .disposed(by: disposeBag)
        
        output.typeIconString
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(typeIconView.rx.text)
            .disposed(by: disposeBag)
        
        output.type
            .map { $0 != .follow }
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(followButton.rx.isHidden)
            .disposed(by: disposeBag)
    }
    
    func shapeCell(item: NotificationCell.Model) -> NotificationCell {
        initialize() // セルの再利用のために各パーツを初期化しておく
        
        // font
        noteView.font = UIFont(name: "Helvetica",
                               size: 11.0)
        
        let viewModel = getViewModel(with: item)
        viewModel.setCell()
        self.viewModel = viewModel
        
        setupGesture(item: item)
        
        return self
    }
    
    private func setupGesture(item: NotificationCell.Model) {
        setTapGesture(disposeBag, closure: {
            guard let noteModel = item.myNote else { return }
            self.delegate?.move2PostDetail(item: noteModel)
        })
        
        // リアクションした者のプロフィールを表示
        for aboutReactee in [nameTextView, iconImageView, emojiView, followButton] {
            aboutReactee?.setTapGesture(disposeBag, closure: {
                guard let userId = item.fromUser?.id else { return }
                self.delegate?.move2Profile(userId: userId)
            })
        }
    }
    
    private func generateEmojiView() -> EmojiView {
        let emojiView = EmojiView()
        
        let sqrt2 = 1.41421356237
        let cos45 = CGFloat(sqrt2 / 2)
        
        let r = iconImageView.frame.width / 2
        let emojiViewRadius = 2 / 3 * r
        
        let basePosition = iconImageView.frame.origin
        let position = CGPoint(x: basePosition.x + cos45 * r,
                               y: basePosition.y + cos45 * r)
        
        emojiView.frame = CGRect(x: position.x,
                                 y: position.y,
                                 width: emojiViewRadius * 2,
                                 height: emojiViewRadius * 2)
        
        emojiView.view.layer.backgroundColor = UIColor(hex: "EE7258").cgColor
        emojiView.view.layer.cornerRadius = emojiViewRadius
        
        return emojiView
    }
}

// MARK: NotificationCell.Model

extension NotificationCell {
    class Model: IdentifiableType, Equatable {
        internal init(isMock: Bool = false, notificationId: String, type: ActionType = .reply, shapedDisplayName: MFMString? = nil, myNote: NoteCell.Model?, replyNote: NoteCell.Model?, fromUser: UserModel?, reaction: String?, emojis: [EmojiModel] = [], ago: String) {
            self.isMock = isMock
            self.notificationId = notificationId
            self.type = type
            self.shapedDisplayName = shapedDisplayName
            self.myNote = myNote
            self.replyNote = replyNote
            self.fromUser = fromUser
            self.reaction = reaction
            self.emojis = emojis
            self.ago = ago
        }
        
        typealias Identity = String
        let identity: String = String(Float.random(in: 1 ..< 100))
        
        var isMock: Bool = false
        
        var notificationId: String
        var type: ActionType = .reply
        
        var shapedDisplayName: MFMString?
        var shapedDescritpion: MFMString?
        
        let myNote: NoteCell.Model? // 自分のどの投稿に対してか
        let replyNote: NoteCell.Model? // 相手の投稿
        
        let fromUser: UserModel?
        
        let reaction: String?
        var emojis: [EmojiModel]
        
        let ago: String
        
        static func == (lhs: NotificationCell.Model, rhs: NotificationCell.Model) -> Bool {
            return lhs.identity == rhs.identity
        }
    }
    
    struct Section {
        var items: [Model]
    }
}

extension NotificationCell.Section: AnimatableSectionModelType {
    typealias Item = NotificationCell.Model
    typealias Identity = String
    
    var identity: String {
        return ""
    }
    
    init(original: NotificationCell.Section, items: [NotificationCell.Model]) {
        self = original
        self.items = items
    }
}
