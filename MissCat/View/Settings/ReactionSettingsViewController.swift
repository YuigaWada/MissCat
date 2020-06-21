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
    
    private var owner: SecureUser? = Cache.UserDefaults.shared.getCurrentUser()
    
    // MARK: LifeCycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupComponents()
        setupCollectionViewLayout()
        setupGesture()
        
        bindTheme()
        setTheme()
        
        let viewModel = setupViewModel()
        viewModel.setEmojiModel()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if let viewModel = viewModel, !viewModel.state.saved {
            viewModel.save()
        }
    }
    
    func setOwner(_ owner: SecureUser) {
        self.owner = owner
        title = owner.instance
    }
    
    // MARK: Design
    
    private func bindTheme() {
        let theme = Theme.shared.theme
        
        theme.map { UIColor(hex: $0.mainColorHex) }.subscribe(onNext: { color in
            self.plusButton.setTitleColor(color, for: .normal)
            self.minusButton.setTitleColor(color, for: .normal)
        }).disposed(by: disposeBag)
        
        theme.map { $0.colorPattern.ui }.subscribe(onNext: { colorPattern in
            self.view.backgroundColor = colorPattern.base
            self.emojiCollectionView.backgroundColor = colorPattern.base
        }).disposed(by: disposeBag)
    }
    
    private func setTheme() {
        if let mainColorHex = Theme.shared.currentModel?.mainColorHex {
            let mainColor = UIColor(hex: mainColorHex)
            plusButton.setTitleColor(mainColor, for: .normal)
            minusButton.setTitleColor(mainColor, for: .normal)
        }
        
        if let colorPattern = Theme.shared.currentModel?.colorPattern.ui {
            view.backgroundColor = colorPattern.base
            emojiCollectionView.backgroundColor = colorPattern.base
        }
    }
    
    /// ステータスバーの文字色
    override var preferredStatusBarStyle: UIStatusBarStyle {
        let currentColorMode = Theme.shared.currentModel?.colorMode ?? .light
        return currentColorMode == .light ? UIStatusBarStyle.default : UIStatusBarStyle.lightContent
    }
    
    // MARK: Setup
    
    private func setupViewModel() -> ReactionSettingsViewModel {
        let input: ReactionSettingsViewModel.Input = .init(owner: owner!)
        let viewModel = ReactionSettingsViewModel(with: input, and: disposeBag)
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
    
    // MARK: Gesture
    
    private func setupGesture() {
        let longGesture = UILongPressGestureRecognizer()
        
        longGesture.cancelsTouchesInView = false
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
            let currentEditState = self.viewModel?.state.editting ?? false
            if currentEditState {
                self.changeEditState(false)
            } else {
                self.showReactionGen()
            }
        }).disposed(by: disposeBag)
        
        minusButton.rx.tap.subscribe(onNext: { _ in
            guard let viewModel = self.viewModel else { return }
            
            let currentEditState = viewModel.state.editting
            self.changeEditState(!currentEditState)
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
            cell.backgroundColor = .clear
            cell.setTitle(headerInfo.title)
            
            return cell
        } else {
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "EmojiCell", for: indexPath) as? EmojiViewCell else { fatalError("Internal Error.") }
            
            cell.mainView.initialize()
            
            cell.mainView.emoji = item
            cell.mainView.isFake = item.isFake
            cell.backgroundColor = .clear
            cell.contentMode = .left
            
            return cell
        }
    }
    
    // MARK: Delegate
    
    // タップ処理
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let viewModel = viewModel else { return }
        
        let index = indexPath.row
        if viewModel.state.editting {
            viewModel.removeCell(index)
            changeEditState(false)
        }
    }
    
    // MARK: Others
    
    @objc func save() {
        viewModel?.save()
    }
    
    private func showReactionGen() {
        guard let reactionGen = getViewController(name: "reaction-gen") as? ReactionGenViewController,
            let owner = owner else { return }
        
        reactionGen.setOwner(owner)
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
    
    private func changeEditState(_ editState: Bool) {
        viewModel?.changeEditState(editState)
        vibrateCell(on: editState)
    }
    
    private func vibrateCell(on vibrated: Bool) {
        emojiCollectionView.visibleCells.forEach { self.view.vibrated(vibrated: vibrated, view: $0) }
    }
}
