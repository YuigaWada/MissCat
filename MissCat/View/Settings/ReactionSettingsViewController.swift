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
    @IBOutlet weak var plusButton: UIButton!
    @IBOutlet weak var minusButton: UIButton!
    
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
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupNavButton()
    }
    
    override func viewWillDisappear(_ animated: Bool) {}
    
    // MARK: Setup
    
    private func setupViewModel() -> ReactionSettingsViewModel {
        let viewModel = ReactionSettingsViewModel(disposeBag)
        let dataSource = setupDataSource()
        
        binding(dataSource: dataSource, viewModel: viewModel)
        self.viewModel = viewModel
        return viewModel
    }
    
    private func setupComponents() {
        emojiCollectionView.register(UINib(nibName: "EmojiViewCell", bundle: nil), forCellWithReuseIdentifier: "EmojiCell")
        emojiCollectionView.rx.setDelegate(self).disposed(by: disposeBag)
        
        plusButton.titleLabel?.font = UIFont.awesomeSolid(fontSize: 14.0)
        minusButton.titleLabel?.font = UIFont.awesomeSolid(fontSize: 14.0)
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
    
    private func setupNavButton() {
        let saveButton = UIBarButtonItem(title: "保存", style: .done, target: self, action: #selector(save))
        navigationItem.rightBarButtonItems = [saveButton]
    }
    
    // MARK: Gesture
    
    private func setupGesture() {
        let longGesture = UILongPressGestureRecognizer()
        
        longGesture.minimumPressDuration = 0.01 // 検知間隔を調整
        longGesture.rx.event.bind { gesture in
            guard let viewModel = self.viewModel, !viewModel.state.editting else { return }
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
        
        plusButton.rx.tap.subscribe(onNext: { _ in
            self.showReactionGen()
        }).disposed(by: disposeBag)
        
        minusButton.rx.tap.subscribe(onNext: { _ in
            guard let viewModel = self.viewModel else { return }
            
            let currentEditState = viewModel.state.editting
            viewModel.changeEditState(!currentEditState)
            self.emojiCollectionView.visibleCells.forEach { self.vibrated(vibrated: !currentEditState, view: $0) }
        }).disposed(by: disposeBag)
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
    
    // MARK: Others
    
    @objc func save() {}
    
    private func showReactionGen() {
        guard let reactionGen = getViewController(name: "reaction-gen") as? ReactionGenViewController else { return }
        
        reactionGen.onPostViewController = true
        reactionGen.selectedEmoji.subscribe(onNext: { emojiModel in // ReactionGenで絵文字が選択されたらに送られてくる
            self.viewModel?.addEmoji(emojiModel)
            reactionGen.dismiss(animated: true, completion: nil)
        }).disposed(by: disposeBag)
        
        presentWithSemiModal(reactionGen, animated: true, completion: nil)
    }
    
    private func getViewController(name: String) -> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyboard.instantiateViewController(withIdentifier: name)
        
        return viewController
    }
    
    private func degreesToRadians(_ degrees: Float) -> Float {
        return degrees * Float(Double.pi) / 180.0
    }
    
    private func vibrated(vibrated: Bool, view: UIView) {
        if vibrated {
            let animation = CABasicAnimation(keyPath: "transform.rotation")
            
            animation.duration = 0.05
            animation.fromValue = degreesToRadians(5.0)
            animation.toValue = degreesToRadians(-5.0)
            animation.repeatCount = Float.infinity
            animation.autoreverses = true
            view.layer.add(animation, forKey: "VibrateAnimationKey")
        } else {
            view.layer.removeAnimation(forKey: "VibrateAnimationKey")
        }
    }
}
