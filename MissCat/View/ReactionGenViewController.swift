//
//  ReactionGenCell.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/17.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import RxDataSources
import RxSwift
import UIKit

public protocol ReactionGenViewControllerDelegate {
    func scrollUp() // 半モーダルviewを上まで引き上げる
}

private typealias ViewModel = ReactionGenViewModel
public typealias EmojisDataSource = RxCollectionViewSectionedReloadDataSource<ReactionGenViewController.EmojisSection>
public class ReactionGenViewController: UIViewController, UISearchBarDelegate, UIScrollViewDelegate, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    @IBOutlet weak var searchBar: UISearchBar!
    @IBOutlet weak var iconImageView: UIImageView!
    @IBOutlet weak var displayNameLabel: UILabel!
    @IBOutlet weak var targetNoteTextView: UITextView!
    
    @IBOutlet weak var settingsButton: UIButton!
    @IBOutlet weak var emojiCollectionView: UICollectionView!
    
    public var delegate: ReactionGenViewControllerDelegate?
    
    private var viewModel: ReactionGenViewModel?
    private let disposeBag = DisposeBag()
    
    private var viewDidAppeared: Bool = false
    private var cellLoading: Bool = false
    private var previousCellCount = -1
    
    private lazy var defaultCellsize = view.frame.width / 8
    
    // MARK: Life Cycle
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupComponents()
        setupCollectionViewLayout()
        
        let viewModel = setupViewModel()
        setEmojiModel(viewModel: viewModel)
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        iconImageView.layer.cornerRadius = iconImageView.frame.width / 2
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        viewDidAppeared = true
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        viewDidAppeared = false
    }
    
    // MARK: Setup
    
    private func setupViewModel() -> ReactionGenViewModel {
        let viewModel = ReactionGenViewModel(and: disposeBag)
        let dataSource = setupDataSource()
        
        binding(dataSource: dataSource, viewModel: viewModel)
        
        self.viewModel = viewModel
        return viewModel
    }
    
    private func setupDataSource() -> EmojisDataSource {
        let dataSource = EmojisDataSource(
            configureCell: { dataSource, _, indexPath, _ in
                self.setupCell(dataSource, self.emojiCollectionView, indexPath)
            }
        )
        
        return dataSource
    }
    
    private func binding(dataSource: EmojisDataSource?, viewModel: ViewModel) {
        guard let dataSource = dataSource else { return }
        
        let output = viewModel.output
        
        Observable.just(viewModel.output.favorites)
            .bind(to: emojiCollectionView.rx.items(dataSource: dataSource))
            .disposed(by: disposeBag)
        
        output.otherEmojis.bind(to: emojiCollectionView.rx.items(dataSource: dataSource)).disposed(by: disposeBag)
    }
    
    private func setupComponents() {
        emojiCollectionView.register(UINib(nibName: "ReactionCollectionHeader", bundle: nil), forCellWithReuseIdentifier: "ReactionCollectionHeader")
        emojiCollectionView.register(UINib(nibName: "EmojiViewCell", bundle: nil), forCellWithReuseIdentifier: "EmojiCell")
        emojiCollectionView.rx.setDelegate(self).disposed(by: disposeBag)
        searchBar.delegate = self
        
        targetNoteTextView.textContainer.lineBreakMode = .byTruncatingTail
        targetNoteTextView.textContainer.maximumNumberOfLines = 2
        
        settingsButton.titleLabel?.font = .awesomeSolid(fontSize: 15.0)
    }
    
    private func setupCollectionViewLayout() {
        let flowLayout = UICollectionViewFlowLayout()
        
        flowLayout.itemSize = CGSize(width: defaultCellsize, height: defaultCellsize)
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        emojiCollectionView.collectionViewLayout = flowLayout
    }
    
    private func setupTapGesture(to view: EmojiViewCell, emoji: String) {
        let tapGesture = UITapGestureRecognizer()
        
        // 各々のEmojiViewに対してtap gestureを付加する
        tapGesture.rx.event.bind { _ in
            guard let targetNoteId = self.viewModel!.targetNoteId else { return }
            
            if self.viewModel!.hasMarked {
                self.viewModel!.cancelReaction(noteId: targetNoteId)
            } else {
                self.viewModel!.registerReaction(noteId: targetNoteId, reaction: ":" + emoji + ":")
            }
            
            self.dismiss(animated: true, completion: nil) // 半モーダルを消す
        }.disposed(by: disposeBag)
        
        view.addGestureRecognizer(tapGesture)
    }
    
    // MARK: Setup Cell
    
    private func setupCell(_ dataSource: CollectionViewSectionedDataSource<ReactionGenViewController.EmojisSection>, _ collectionView: UICollectionView, _ indexPath: IndexPath) -> UICollectionViewCell {
        let index = indexPath.row
        let item = dataSource.sectionModels[0].items[index]
        
        let isHeader = item is EmojiViewHeader
        if isHeader {
            guard let headerInfo = item as? EmojiViewHeader,
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ReactionCollectionHeader", for: indexPath) as? ReactionCollectionHeader else { fatalError("Internal Error.") }
            
            cell.contentMode = .left
            cell.setTitle(headerInfo.title)
            return cell
        } else {
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "EmojiCell", for: indexPath) as? EmojiViewCell else { fatalError("Internal Error.") }
            
            cell.mainView.initialize()
            
            cell.mainView.emoji = item
            cell.mainView.isFake = item.isFake
            cell.contentMode = .left
            setupTapGesture(to: cell, emoji: item.rawEmoji)
            
            return cell
        }
    }
    
    // MARK: Set Methods
    
    private func setEmojiModel(viewModel: ReactionGenViewModel) {
        viewModel.setEmojiModel()
    }
    
    private func setTargetNoteId(_ id: String?) {
        viewModel!.targetNoteId = id
    }
    
    // MARK: CollectionView Delegate

    // Headerセルの場合はの幅を設定
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let defaultSize = CGSize(width: defaultCellsize, height: defaultCellsize)
        guard let viewModel = viewModel else { return defaultSize }
        let isHeader = viewModel.checkHeader(index: indexPath.row)
        
        return isHeader ? CGSize(width: emojiCollectionView.frame.width, height: 30) : defaultSize
    }
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 0
    }
    
    // MARK: Public Methods
    
    public func setTargetNote(noteId: String, iconUrl: String?, displayName: String, username: String, note: NSAttributedString, hasFile: Bool, hasMarked: Bool) {
        // noteId
        setTargetNoteId(noteId)
        
        // icon image
        if let image = Cache.shared.getIcon(username: username) {
            iconImageView.image = image
        } else if let iconUrl = iconUrl, let url = URL(string: iconUrl) {
            url.toUIImage { [weak self] image in
                guard let self = self, let image = image else { return }
                
                DispatchQueue.main.async {
                    Cache.shared.saveIcon(username: username, image: image) // CHACHE!
                    self.iconImageView.image = image
                }
            }
        }
        
        // displayName
        displayNameLabel.text = displayName
        
        // note
        targetNoteTextView.attributedText = note // .changeColor(to: .lightGray)
        targetNoteTextView.alpha = 0.5
    }
    
    // MARK: TextField Delegate
    
    public func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        guard let delegate = delegate else { return }
        
        delegate.scrollUp()
    }
}
