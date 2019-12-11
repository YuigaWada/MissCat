//
//  ReactionGenCell.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/17.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit
import RxSwift
import RxDataSources


public protocol ReactionGenViewControllerDelegate {
    func scrollUp() //半モーダルviewを上まで引き上げる
}


public typealias EmojisDataSource = RxCollectionViewSectionedReloadDataSource<ReactionGenViewController.EmojisSection>
public class ReactionGenViewController: UIViewController, UITextFieldDelegate, UIScrollViewDelegate {
    
    @IBOutlet weak var iconImageView: UIImageView!
    @IBOutlet weak var displayNameLabel: UILabel!
    @IBOutlet weak var targetNoteTextView: UITextView!
    @IBOutlet weak var textFiled: UITextField!
    
    @IBOutlet weak var emojiCollectionView: UICollectionView!
    
    
    public var delegate: ReactionGenViewControllerDelegate?
    
    private lazy var viewModel: ReactionGenViewModel = .init(disposeBag: disposeBag)
    private let disposeBag = DisposeBag()
    
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        self.setupComponents()
        self.setupCollectionViewLayout()
        
        let dataSource = self.setupDataSource()
        self.binding(dataSource: dataSource)
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.iconImageView.layer.cornerRadius =  self.iconImageView.frame.width / 2
    }
    
    private func setupDataSource()-> EmojisDataSource {
        let dataSource = EmojisDataSource(
            configureCell: { dataSource, tableView, indexPath, item in
                return self.setupCell(dataSource, self.emojiCollectionView, indexPath)
        })
        
        return dataSource
    }
    
    private func binding(dataSource: EmojisDataSource?) {
        guard let dataSource = dataSource else { return }
        
        let presets = viewModel.getPresets()
        
        Observable.just(presets)
            .bind(to: self.emojiCollectionView.rx.items(dataSource: dataSource))
            .disposed(by: disposeBag)
        
    }
    
    
    
    private func setupComponents() {
        self.emojiCollectionView.register(UINib(nibName: "EmojiViewCell", bundle: nil), forCellWithReuseIdentifier: "EmojiCell")
        self.emojiCollectionView.rx.setDelegate(self).disposed(by: disposeBag)
        self.textFiled.delegate = self
        
    
        targetNoteTextView.textContainer.lineBreakMode = .byTruncatingTail
        targetNoteTextView.textContainer.maximumNumberOfLines = 2
    }
    
    private func setupCollectionViewLayout() {
        let flowLayout = UICollectionViewFlowLayout()
        let size = self.view.frame.width / 7
        
        flowLayout.itemSize = CGSize(width: size, height: size)
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        self.emojiCollectionView.collectionViewLayout = flowLayout
    }
    
    
    //MARK: Setup Cell
    private func setupCell(_ dataSource: CollectionViewSectionedDataSource<ReactionGenViewController.EmojisSection>, _ collectionView: UICollectionView, _ indexPath: IndexPath)-> UICollectionViewCell {
        let index = indexPath.row
        let item = dataSource.sectionModels[0].items[index]
        
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "EmojiCell", for: indexPath) as? EmojiViewCell else {fatalError("Internal Error.")}
        
        cell.mainView.emoji = item.defaultEmoji ?? "👍"
//        cell.frame = CGRect(x: cell.frame.origin.x,
//                            y: cell.frame.origin.y,
//                            width: self.view.frame.width / 7,
//                            height: self.view.frame.width / 7)
        setupTapGesture(to: cell, emoji: item.defaultEmoji ?? "👍")
        
        
        return cell
    }
    
    
    public func setTargetNoteId(_ id: String?) {
        viewModel.targetNoteId = id
    }
    
    private func setupTapGesture(to view: EmojiViewCell, emoji: String) {
        
        let tapGesture = UITapGestureRecognizer()
        
        //各々のEmojiViewに対してtap gestureを付加する
        tapGesture.rx.event.bind{ _ in
            guard let targetNoteId = self.viewModel.targetNoteId else { return }
            
            if self.viewModel.hasMarked {
                self.viewModel.cancelReaction(noteId: targetNoteId)
            }
            else {
                self.viewModel.registerReaction(noteId: targetNoteId, reaction: emoji)
            }
            
            self.dismiss(animated: true, completion: nil) // 半モーダルを消す
        }.disposed(by: disposeBag)
        
        view.addGestureRecognizer(tapGesture)
    }
    
    
    //MARK: Public Methods
    public func setTargetNote(noteId: String, iconUrl: String?, displayName: String, username: String, note: NSAttributedString, hasFile: Bool, hasMarked: Bool) {
        
        // noteId
        self.setTargetNoteId(noteId)
        
        // icon image
        if let image = Cache.shared.getIcon(username: username) {
            self.iconImageView.image = image
        }
        else if let iconUrl = iconUrl, let url = URL(string: iconUrl) {
            url.toUIImage{ [weak self] image in
                guard let self = self, let image = image else { return }
                
                DispatchQueue.main.async {
                    Cache.shared.saveIcon(username: username, image: image) // CHACHE!
                    self.iconImageView.image = image
                }
            }
        }
        
        // displayName
        self.displayNameLabel.text = displayName
        
        // note
        self.targetNoteTextView.attributedText = note //.changeColor(to: .lightGray)
        self.targetNoteTextView.alpha = 0.5
    }
    
    //MARK: TextField Delegate
    public func textFieldDidBeginEditing(_ textField: UITextField) {
        guard let delegate = delegate else { return }
        
        delegate.scrollUp()
    }
    
}



//MARK: ReactionGenCell.Model

public extension ReactionGenViewController {
    struct EmojisSection {
        public var items: [Item]
    }
    
    struct EmojiModel {
        public let isDefault: Bool
        public let defaultEmoji: String?
        public let customEmojiUrl: String?
    }
}


extension ReactionGenViewController.EmojisSection: SectionModelType {
    public typealias Item = ReactionGenViewController.EmojiModel
    
    public init(original: ReactionGenViewController.EmojisSection, items: [Item]) {
        self = original
        self.items = items
    }
}
