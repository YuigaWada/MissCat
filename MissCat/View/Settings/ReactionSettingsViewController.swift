//
//  ReactionSettingsViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/05.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxCocoa
import RxDataSources
import RxSwift
import UIKit

class ReactionSettingsViewController: UIViewController, UICollectionViewDelegate {
    @IBOutlet weak var emojiCollectionView: UICollectionView!
    
    private lazy var defaultCellsize = view.frame.width / 8
    
    private var viewModel: ReactionSettingsViewModel?
    private let disposeBag = DisposeBag()
    
    // MARK: LifeCycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupComponents()
        setupCollectionViewLayout()
        setupGesture()
        
        let viewModel = setupViewModel()
        viewModel.setEmojiModel()
    }
    
    // MARK: Setup
    
    private func setupViewModel() -> ReactionSettingsViewModel {
        let viewModel = ReactionSettingsViewModel(disposeBag)
        let dataSource = setupDataSource()
        
        binding(dataSource: dataSource, viewModel: viewModel)
        self.viewModel = viewModel
        return viewModel
    }
    
    private func setupComponents() {
        emojiCollectionView.register(UINib(nibName: "ReactionCollectionHeader", bundle: nil), forCellWithReuseIdentifier: "ReactionCollectionHeader")
        emojiCollectionView.register(UINib(nibName: "EmojiViewCell", bundle: nil), forCellWithReuseIdentifier: "EmojiCell")
        emojiCollectionView.rx.setDelegate(self).disposed(by: disposeBag)
    }
    
    private func setupCollectionViewLayout() {
        let flowLayout = UICollectionViewFlowLayout()
        
        flowLayout.itemSize = CGSize(width: defaultCellsize, height: defaultCellsize)
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        emojiCollectionView.collectionViewLayout = flowLayout
    }
    
    private func setupDataSource() -> EmojisDataSource {
        let dataSource = EmojisDataSource(
            configureCell: { dataSource, _, indexPath, _ in
                self.setupCell(dataSource, self.emojiCollectionView, indexPath)
            },
            moveItem: { _, sourceIndexPath, destinationIndexPath in
                self.viewModel?.moveItem(moveItemAt: sourceIndexPath, to: destinationIndexPath)
            },
            canMoveItemAtIndexPath: { _, _ in
                true
            }
        )
        
        return dataSource
    }
    
    // MARK: Gesture
    
    private func setupGesture() {
        let longGesture = UILongPressGestureRecognizer()
        
        longGesture.rx.event.bind { gesture in
            self.handleGesture(with: gesture)
        }.disposed(by: disposeBag)
        
        emojiCollectionView.addGestureRecognizer(longGesture)
    }
    
    private func handleGesture(with gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard let selectedIndexPath = emojiCollectionView.indexPathForItem(at: gesture.location(in: emojiCollectionView)) else {
                break
            }
            emojiCollectionView.beginInteractiveMovementForItem(at: selectedIndexPath)
            
        case .changed:
            emojiCollectionView.updateInteractiveMovementTargetPosition(gesture.location(in: gesture.view))
            
        case .ended:
            emojiCollectionView.endInteractiveMovement()
            
        default:
            emojiCollectionView.cancelInteractiveMovement()
        }
    }
    
    // MARK: Binding
    
    private func binding(dataSource: EmojisDataSource?, viewModel: ReactionSettingsViewModel) {
        guard let dataSource = dataSource else { return }
        
        let output = viewModel.output
        output.favs.bind(to: emojiCollectionView.rx.items(dataSource: dataSource)).disposed(by: disposeBag)
    }
    
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
            
            return cell
        }
    }
}
